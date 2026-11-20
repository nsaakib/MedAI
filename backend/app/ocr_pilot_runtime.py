import math
import unicodedata
from pathlib import Path
import torch
from PIL import Image

FIELDS = ('medicine','strength','dosage_form','frequency','meal','duration','route','special_instruction')
ROUTES = {
    'medicine': '03C TrOCR',
    'strength': '03C TrOCR',
    'dosage_form': '03C TrOCR',
    'frequency': '03S',
    'duration': '03S',
}

def norm(s):
    return ' '.join(unicodedata.normalize('NFC', s).split())

def load_trocr(path, device):
    from transformers import TrOCRProcessor, VisionEncoderDecoderModel
    proc = TrOCRProcessor.from_pretrained(str(path), local_files_only=True)
    model = VisionEncoderDecoderModel.from_pretrained(str(path), local_files_only=True).to(device).eval()
    @torch.inference_mode()
    def predict(crops):
        result = []
        for i in range(0, len(crops), 4):
            x = proc(images=crops[i:i+4], return_tensors='pt').pixel_values.to(device)
            ids = model.generate(x, num_beams=2, max_new_tokens=64)
            result.extend(norm(s) for s in proc.batch_decode(ids, skip_special_tokens=True))
        return result
    return predict

def load_03s(pt):
    import numpy as np
    import torch
    from torch import nn
    from torch.nn.utils.rnn import pack_padded_sequence,pad_packed_sequence

    state=torch.load(pt,map_location='cpu',weights_only=True)
    if not isinstance(state, dict) or not {'model','chars','height','width'} <= state.keys():
        raise ValueError(f'{pt} is readable but does not have the expected 03S checkpoint fields.')
    chars=state['chars']; H,W=state['height'],state['width']
    assert (H,W)==(48,320)
    def encode_image(im):
        scale=min(H/im.height,W/im.width)
        h=max(1,min(H,round(im.height*scale))); w=max(1,min(W,round(im.width*scale)))
        im=im.resize((w,h),Image.Resampling.BILINEAR)
        a=np.zeros((H,W),np.float32)
        top=(H-h)//2
        a[top:top+h,:w]=1-np.asarray(im,dtype=np.float32)/255.
        return torch.from_numpy(a).unsqueeze(0),max(32,(w+3)//4)

    class CRNN(nn.Module):
        def __init__(self):
            super().__init__()
            layers=[]
            for inp,out,pool in ((1,32,(2,2)),(32,64,(2,2)),(64,96,(2,1)),(96,128,(2,1))):
                layers.extend([nn.Conv2d(inp,out,3,padding=1),nn.BatchNorm2d(out),nn.ReLU(),nn.MaxPool2d(pool)])
            self.cnn=nn.Sequential(*layers,nn.AdaptiveAvgPool2d((1,None)))
            self.rnn=nn.GRU(128,96,bidirectional=True,batch_first=True)
            self.out=nn.Linear(192,len(chars)+1)
        def forward(self,x,lens):
            x=self.cnn(x).squeeze(2).transpose(1,2)
            x,_=self.rnn(pack_padded_sequence(x,lens,batch_first=True,enforce_sorted=False))
            x,_=pad_packed_sequence(x,batch_first=True)
            return self.out(x).log_softmax(-1).transpose(0,1)

    def decode(ids):
        out=[];last=0
        for i in ids:
            if i and i!=last:out.append(chars[i-1])
            last=i
        return norm(''.join(out))


    model = CRNN()
    model.load_state_dict(state['model'], strict=True)
    model.eval()
    @torch.inference_mode()
    def predict(im):
        x, n = encode_image(im.convert('L'))
        return decode(model(x[None], torch.tensor([n])).argmax(-1)[:,0].tolist())
    return predict


def load_detector(file,device='cpu'):
    from torchvision.models.detection import fasterrcnn_mobilenet_v3_large_fpn
    from torchvision.models.detection.faster_rcnn import FastRCNNPredictor
    from torchvision.ops.misc import FrozenBatchNorm2d
    ck=torch.load(file,map_location='cpu',weights_only=True)
    cfg=ck['config'];classes=ck['class_to_id']
    if cfg.get('method')!='all_fields_plus_unknown_v1' or set(classes)!=set(FIELDS)|{'text_unknown'}:
        raise ValueError('Use the 03P expanded62 detector checkpoint.')
    lo,hi=cfg['resolution']
    m=fasterrcnn_mobilenet_v3_large_fpn(weights=None,weights_backbone=None,min_size=lo,max_size=hi,
                                       rpn_score_thresh=.05,box_score_thresh=0.,box_detections_per_img=300)
    def convert(module):
        for name,child in list(module.named_children()):
            if isinstance(child,torch.nn.BatchNorm2d):
                setattr(module,name,FrozenBatchNorm2d(child.num_features,eps=child.eps))
            else:convert(child)
    convert(m)
    m.roi_heads.box_predictor=FastRCNNPredictor(m.roi_heads.box_predictor.cls_score.in_features,len(classes)+1)
    m.load_state_dict(ck['state_dict'],strict=True)
    return m.to(device).eval(),{int(v):k for k,v in classes.items()}

@torch.inference_mode()
def proposals(model,labels,im,device='cpu'):
    from torchvision.transforms.functional import to_tensor
    pred=model([to_tensor(im).to(device)])[0]
    boxes=pred['boxes'].cpu().tolist();scores=pred['scores'].cpu().tolist();ids=pred['labels'].cpu().tolist()
    result=[]
    for b,s,k in zip(boxes,scores,ids):
        label=labels[k]
        if s<.35 or label not in FIELDS:continue
        x,y,x2,y2=b;w,h=im.size
        clamp=lambda v: max(0.,min(1.,v))
        box=[clamp(x/w),clamp(y/h),clamp(x2/w),clamp(y2/h)]
        if box[2]>box[0] and box[3]>box[1]:result.append((label,box))
        if len(result)>=100:break
    return sorted(result,key=lambda x:(x[1][1],x[1][0]))

def crop_box(im,box):
    w,h=im.size
    x,y,x2,y2=box
    return im.crop((math.floor(x*w),math.floor(y*h),math.ceil(x2*w),math.ceil(y2*h)))
