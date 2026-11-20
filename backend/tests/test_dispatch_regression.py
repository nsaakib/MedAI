from concurrent.futures import ThreadPoolExecutor
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from app.main import create_app
from app.sos_dispatch import now


def account(client, name):
    password='a good sandbox password'
    session=client.post('/api/auth/register',json=dict(name=name,email=f'{name}@example.test',password=password))
    assert session.status_code==201,session.json()
    return {'Authorization':'Bearer '+session.json()['token']}


def partner(client, name, loc=(23.78,90.40)):
    headers=account(client,name)
    res=client.post('/api/sos/partner/enrollment',headers=headers,
        json=dict(name=name,organization=name,address='Fictional hospital',phone='01700000000',lat=loc[0],lng=loc[1]))
    assert res.status_code==201,res.json()
    info=res.json()
    org=info['organization_id']
    d=client.post('/api/auth/login',json=dict(email=info['driver_email'],password=info['driver_password']))
    assert d.status_code==200
    driver={'Authorization':'Bearer '+d.json()['token']}
    op=f'/api/sos/operator/{org}'
    jobs=f'/api/sos/driver/{org}/jobs'
    board=client.post(op+'/board',headers=headers).json()
    return headers, driver, op, jobs, board['fleet'][0]['id'],org


def body(key,category='basic',equipment=('oxygen',),consent=True):
    return dict(lat=23.78,lng=90.40,consent=True,allow_reroute=consent,phone='01700000000',
                request_key=key,category=category,equipment=list(equipment),address='Fictional pickup')


def client_for(tmp_path):
    app=create_app(tmp_path,Fernet.generate_key(),False,sos_sandbox=True)
    return app,TestClient(app,base_url='http://127.0.0.1:8001')


def configure(c,p,category):
    return c.post(f'/api/sos/partner/{p[5]}/test-fleet',headers=p[0],
                  json={'vehicle_id':p[4],'category':category})


def request(c,pat,key,**kw):
    r=c.post('/api/sos/requests',headers=pat,json=body(key,**kw))
    assert r.status_code==200,r.json()
    return r.json()


def reserve(c,p,item):
    return c.post(p[2]+'/requests/'+item['id']+'/assign',headers=p[0],json={'vehicle_id':p[4]})


def test_screenshot_and_full_advanced_trip(tmp_path):
    app,c=client_for(tmp_path)
    p=partner(c,'organization')
    pat=account(c,'patient')
    other=account(c,'outsider')
    req=body('screen_reproduction_01',equipment=('oxygen','stretcher','ventilator'))
    f={k:req[k] for k in ('lat','lng','equipment','category')}
    results=c.post('/api/sos/nearby',headers=pat,json=f).json()
    assert results[0]['compatible_fleet']==results[0]['dispatch_slots']==0
    first=request(c,pat,'screen_reproduction_01',equipment=('oxygen','stretcher','ventilator'))
    assert first['status']=='no_coverage' and first['reason']=='equipment_or_category_unavailable'
    assert c.post(p[2]+'/board',headers=p[0]).json()['requests']==[]
    assert c.post(f'/api/sos/partner/{p[5]}/test-fleet',headers=other,
                  json={'vehicle_id':p[4],'category':'advanced'}).status_code==404
    assert configure(c,p,'advanced').status_code==200
    assert request(c,pat,'screen_reproduction_02',equipment=('ventilator',))['status']=='no_coverage'  # Basic is still strict.
    new=request(c,pat,'screen_reproduction_03',category='advanced',equipment=('oxygen','stretcher','ventilator'))
    assert new['status']=='queued' and new['org']['id']==p[5]
    assert configure(c,p,'basic').status_code==409
    held=reserve(c,p,new).json()
    assert held['status']=='awaiting_driver' and held['assignment']['sms']['state']=='manual'
    assert 'patient' not in c.get(p[3],headers=p[1]).json()[0]
    assert c.get('/api/sos/requests',headers=pat).json()[0]['assignment']['driver'] is None
    job=p[3]+'/'+held['assignment']['id']
    for action,status in [('accept','dispatched'),('en_route','en_route'),('arrived','arrived'),('complete','completed')]:
        assert c.post(job,headers=p[1],json={'action':action}).json()['status']==status
        assert c.get('/api/sos/requests',headers=pat).json()[0]['status']==status


def test_balancing_and_no_match_reason(tmp_path):
    app,c=client_for(tmp_path)
    partners=[partner(c,'partner-a'),partner(c,'partner-b',(23.783,90.40))]
    h=[account(c,'patient-a'),account(c,'patient-b'),account(c,'patient-c')]
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs=list(pool.map(lambda n:request(c,h[n],f'patient_balancing_{n:03}'),range(2)))
    assert sorted(j['org']['id'] for j in jobs)==sorted(p[5] for p in partners)
    assert {j['status'] for j in jobs}=={'queued'}
    third=request(c,h[2],'patient_balancing_002')
    assert third['reason']=='matching_vehicles_busy'


def test_decline_fails_over_without_sharing_with_declined_partner(tmp_path):
    app,c=client_for(tmp_path)
    partners=[partner(c,'partner-a'),partner(c,'partner-b')]
    h=account(c,'patient')
    first=request(c,h,'partner_decline_001')
    old=next(p for p in partners if p[5]==first['org']['id'])
    replacement=next(p for p in partners if p is not old)
    path=old[2]+'/requests/'+first['id']+'/decline'
    assert c.post(path,headers=old[0],json={}).json()['status']=='queued'
    routed=c.get('/api/sos/requests',headers=h).json()[0]
    assert routed['id']==first['id'] and routed['rerouted']
    assert routed['org']['id']==replacement[5] and 'assignment' not in routed
    assert c.post(old[2]+'/board',headers=old[0]).json()['requests']==[]
    assert reserve(c,old,first).status_code==404
    assert reserve(c,replacement,first).status_code==200


def test_driver_timeout_and_stale_accept(tmp_path):
    app,c=client_for(tmp_path)
    partners=[partner(c,'partner-a'),partner(c,'partner-b')]
    h=account(c,'patient')
    first=request(c,h,'test_driver_timeout_0001')
    old=next(p for p in partners if p[5]==first['org']['id'])
    replacement=next(p for p in partners if p is not old)
    held=reserve(c,old,first).json()
    with app.state.store.db() as db:
        db.execute('UPDATE sos_requests SET deadline=? WHERE id=?',(now()-1,first['id']))
    fresh=c.get('/api/sos/requests',headers=h).json()[0]
    assert fresh['org']['id']==replacement[5] and fresh['status']=='queued'
    late=old[3]+'/'+held['assignment']['id']
    assert c.post(late,headers=old[1],json={'action':'accept'}).status_code==404
    new=reserve(c,replacement,fresh).json()
    rid=new['assignment']['id']
    assert c.post(replacement[3]+'/'+rid,headers=replacement[1],json={'action':'accept'}).json()['status']=='dispatched'


def test_reroute_requires_consent_and_stays_sandbox_only(tmp_path):
    app,c=client_for(tmp_path)
    partners=[partner(c,'partner-a'),partner(c,'partner-b')]
    h=account(c,'patient')
    first=request(c,h,'legacy_consent_request_0001',consent=False)
    old=next(p for p in partners if p[5]==first['org']['id'])
    assert c.post(old[2]+'/requests/'+first['id']+'/decline',headers=old[0],json={}).json()['status']=='no_coverage'
    assert c.get('/api/sos/requests',headers=h).json()[0]['org']['id']==old[5]
    assert request(c,h,'legacy_consent_request_0001',consent=False)['id']==first['id']
    app.state.sos_sandbox=False  # endpoint refuses changes even from an operator if not sandbox
    assert configure(c,old,'advanced').status_code==404


def test_queued_general_request_does_not_consume_only_advanced_vehicle():
    from app.sos_dispatch import spare_vehicles, ranked
    advanced={'id':'a','status':'available','equipment':['oxygen','ventilator'],
              'category':'advanced','distance_km':0.1}
    basic={'id':'b','status':'available','equipment':['oxygen'],
           'category':'basic','distance_km':0.3}
    fleet=[advanced,basic]
    general={'equipment':['oxygen'], 'category':None}
    fitting=ranked(fleet,['ventilator'],'advanced')
    assert spare_vehicles(fleet,[general],fitting)==[advanced]
    assert spare_vehicles([advanced],[general],fitting)==[]
    reserved_for_specific={'equipment':['ventilator'],'category':'advanced'}
    assert spare_vehicles(fleet,[general,reserved_for_specific],fitting)==[]


def test_operator_timeout_advances_then_finishes_with_no_coverage(tmp_path):
    app,c=client_for(tmp_path)
    partners=[partner(c,'partner-a'),partner(c,'partner-b')]
    h=account(c,'patient')
    first=request(c,h,'test_operator_timeout_01')
    old=next(p for p in partners if p[5]==first['org']['id'])
    for ix in range(2):
        with app.state.store.db() as db:
            db.execute('UPDATE sos_requests SET deadline=? WHERE id=?',(now()-1,first['id']))
        fresh=c.get('/api/sos/requests',headers=h).json()[0]
        assert fresh['id']==first['id']
        if ix==0:
            assert fresh['status']=='queued' and fresh['org']['id']!=old[5]
        else:
            assert fresh['status']=='no_coverage' and fresh['reason']=='partners_exhausted'
    assert c.post(old[2]+'/board',headers=old[0]).json()['requests']==[]


def test_operator_cannot_take_scarce_vehicle_when_other_matching_vehicle_exists(tmp_path):
    app,c=client_for(tmp_path)
    main=partner(c,'main-team')
    another=partner(c,'second-team')
    assert configure(c,main,'advanced').status_code==200
    with app.state.store.db() as db:
        db.execute("UPDATE sos_members SET org_id=? WHERE org_id=? AND role='driver'",(main[5], another[5]))
        db.execute('UPDATE sos_vehicles SET org_id=? WHERE id=?',(main[5],another[4]))
        db.execute('UPDATE sos_orgs SET verified=0 WHERE id=?',(another[5],))
    general=account(c,'general-patient')
    specific=account(c,'equipment-patient')
    left=request(c,general,'general_waiting_001',category=None)
    right=request(c,specific,'specific_waiting_01',category='advanced',equipment=('ventilator',))
    assert left['status']==right['status']=='queued'
    queue=c.post(main[2]+'/board',headers=main[0]).json()['requests']
    assert next(x for x in queue if x['id']==left['id'])['recommended'][0]['id']==another[4]
    assert reserve(c,main,left).status_code==409
    assert reserve(c,main,right).status_code==200
    assert c.post(main[2]+'/requests/'+left['id']+'/assign',headers=main[0],
                  json={'vehicle_id':another[4]}).status_code==200
