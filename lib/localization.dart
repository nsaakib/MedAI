import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UiLanguage {
  static final locale = ValueNotifier<Locale>(const Locale('en'));
  static const _storage = FlutterSecureStorage();
  static Future<void> initialize() async {
    try {
      use(await _storage.read(key: 'medai_ui_language') ?? 'en');
    } catch (_) {}
  }

  static void use(String value) {
    final next = Locale(
      ['bn', 'Bangla', 'বাংলা', 'Bengali'].contains(value) ? 'bn' : 'en',
    );
    if (locale.value != next) locale.value = next;
  }

  static Future<void> save(String code) async {
    await _storage.write(key: 'medai_ui_language', value: code);
    use(code);
  }
}

T tr<T extends String?>(T value) {
  if (value == null || UiLanguage.locale.value.languageCode != 'bn')
    return value;
  final source = value as String;
  final exact = _bangla[source];
  if (exact != null) return exact as T;
  for (final entry in _templates.entries) {
    final match = entry.value.firstMatch(source);
    if (match == null) continue;
    var index = 0;
    return _bangla[entry.key]!.replaceAllMapped(
          RegExp(r'\{value\}'),
          (_) => match.group(++index) ?? '',
        )
        as T;
  }
  return value;
}

final _templates = <String, RegExp>{
  for (final key in _bangla.keys)
    if (key.contains('{value}'))
      key: RegExp(
        '^' +
            key.split('{value}').map(RegExp.escape).join(r'([\s\S]*?)') +
            r'$',
      ),
};

const _primaryBangla = <String, String>{
  "For report analysis, relevant report text and your question are sent to the configured AI provider. If text is missing, the report image may be read by Groq. With Ollama, processing stays on your server. Verify results against the original.":
      "রিপোর্ট বিশ্লেষণের জন্য প্রাসঙ্গিক লেখা ও আপনার প্রশ্ন নির্বাচিত AI সেবায় পাঠানো হবে। লেখা না থাকলে Groq দিয়ে রিপোর্টের ছবি পড়া হতে পারে। Ollama ব্যবহার করলে প্রক্রিয়াকরণ আপনার সার্ভারেই থাকে। মূল রিপোর্টের সঙ্গে ফলাফল মিলিয়ে নিন।",
  "Report details used": "বিশ্লেষণে ব্যবহৃত রিপোর্টের তথ্য",
  "Actual text retrieved from your uploaded report. Check recognition against the original.":
      "আপনার আপলোড করা রিপোর্ট থেকে পাওয়া আসল লেখা। মূল রিপোর্টের সঙ্গে মিলিয়ে নিন।",
  "View original report": "মূল রিপোর্ট দেখুন",

  "Uploading prescription…": "প্রেসক্রিপশনের ছবি আপলোড হচ্ছে…",
  "Sign in again before uploading this prescription.":
      "প্রেসক্রিপশন আপলোড করতে আবার সাইন ইন করুন।",
  "Your account changed. Open the prescription again.":
      "অ্যাকাউন্ট পরিবর্তন হয়েছে। প্রেসক্রিপশনটি আবার খুলুন।",
  "Another sync is still running. Wait for it to finish, then retry the prescription upload.":
      "অন্য তথ্য সিঙ্ক হচ্ছে। শেষ হলে প্রেসক্রিপশন আপলোড আবার চেষ্টা করুন।",
  "The local image is unavailable for upload. Select the prescription photo again.":
      "আপলোডের জন্য ছবিটি পাওয়া যায়নি। প্রেসক্রিপশনের ছবি আবার নির্বাচন করুন।",
  "The image could not be uploaded. Check Tailscale and your connection, then retry. Your queued photo is kept.":
      "ছবি আপলোড হয়নি। Tailscale ও সংযোগ যাচাই করে আবার চেষ্টা করুন। ছবিটি অপেক্ষমাণ তালিকায় রাখা আছে।",
  "This image is too large. Choose a smaller prescription photo.":
      "ছবিটি অনেক বড়। ছোট আকারের প্রেসক্রিপশনের ছবি নির্বাচন করুন।",
  "The image format is unsupported. Select a JPG or PNG photo.":
      "এই ছবির ফরম্যাট সমর্থিত নয়। JPG বা PNG ছবি নির্বাচন করুন।",
  "This upload conflicts with an existing document. Select the prescription photo again.":
      "এই আপলোডের সঙ্গে আগের নথির দ্বন্দ্ব রয়েছে। প্রেসক্রিপশনের ছবি আবার নির্বাচন করুন।",
  "The prescription could not be processed. Check the connection and retry.":
      "প্রেসক্রিপশন প্রক্রিয়া করা যায়নি। সংযোগ যাচাই করে আবার চেষ্টা করুন।",

  "Status updated from the server.": "সার্ভার থেকে অবস্থা হালনাগাদ হয়েছে।",
  "Status checked: live dispatch is disabled on this server. Refresh does not enable it.":
      "অবস্থা যাচাই হয়েছে: এই সার্ভারে সরাসরি অ্যাম্বুলেন্স পাঠানো বন্ধ আছে। রিফ্রেশ করলে এটি চালু হয় না।",
  "The server owner must configure verified partners and fleet access before enabling live requests. For fictional testing, start the separate sandbox server.":
      "সরাসরি অনুরোধ চালুর আগে সার্ভারের মালিককে যাচাইকৃত প্রতিষ্ঠান ও অ্যাম্বুলেন্সের ব্যবস্থা করতে হবে। কাল্পনিক পরীক্ষার জন্য আলাদা স্যান্ডবক্স সার্ভার চালু করুন।",
  "Open Partner Operations": "পার্টনার পরিচালনা খুলুন",
  "Could not open Partner Operations. Check your connection.":
      "পার্টনার পরিচালনা খোলা যায়নি। সংযোগ যাচাই করুন।",
  "Sign in again to refresh your ambulance requests.":
      "অ্যাম্বুলেন্স অনুরোধ হালনাগাদ করতে আবার সাইন ইন করুন।",
  "The server refused dispatch access. Ask the server owner to check the HTTPS proxy configuration.":
      "সার্ভার অনুরোধ গ্রহণ করেনি। সার্ভারের মালিককে HTTPS প্রক্সি সেটিং যাচাই করতে বলুন।",

  "A cost estimate for a pharmacy that sells individual units. It is not an Arogga order or a change to your prescription. Confirm availability and ask your pharmacist about any shortfall.":
      "খুচরা ওষুধ বিক্রি করে এমন ফার্মেসির জন্য খরচের হিসাব। এটি Arogga অর্ডার বা প্রেসক্রিপশনের পরিবর্তন নয়। সরবরাহ ও ঘাটতি সম্পর্কে ফার্মাসিস্টের সঙ্গে কথা বলুন।",
  "A member of your configured care team will review your request.":
      "আপনার চিকিৎসা দলের একজন সদস্য অনুরোধটি পর্যালোচনা করবেন।",
  "AI can make mistakes. Check important information.":
      "এআই ভুল করতে পারে। গুরুত্বপূর্ণ তথ্য যাচাই করুন।",
  "AI setup needed · Check connection":
      "এআই সেটআপ প্রয়োজন · সংযোগ পরীক্ষা করুন",
  "AMBULANCE SERVICE": "অ্যাম্বুলেন্স সেবা",
  "Account access": "অ্যাকাউন্টে প্রবেশ",
  "Add Document": "নথি যোগ করুন",
  "Add Manual Reading": "নিজে পরিমাপ লিখুন",
  "Add Medicine": "ওষুধ যোগ করুন",
  "Add Medicine Manually": "নিজে ওষুধ লিখে যোগ করুন",
  "Add a pickup location, valid Bangladesh mobile number, and sharing consent.":
      "পিকআপ স্থান, সঠিক বাংলাদেশি মোবাইল নম্বর এবং তথ্য ভাগ করার সম্মতি দিন।",
  "Add document": "নথি যোগ করুন",
  "Add reminder": "রিমাইন্ডার যোগ করুন",
  "Add requesting doctor (optional)":
      "পরীক্ষা দেওয়া চিকিৎসক যোগ করুন (ঐচ্ছিক)",
  "Add your first measurement below.": "নিচে আপনার প্রথম পরিমাপ লিখুন।",
  "Add {value}": "{value} যোগ করুন",
  "Address or landmark (optional)": "ঠিকানা বা পরিচিত স্থান (ঐচ্ছিক)",
  "Adjust budget": "বাজেট পরিবর্তন করুন",
  "Adjust budget / delivery": "বাজেট / ডেলিভারি খরচ পরিবর্তন করুন",
  "Advanced": "উন্নত",
  "All changes synced": "সব পরিবর্তন সিঙ্ক হয়েছে",
  "All divisions": "সব বিভাগ",
  "All languages": "সব ভাষা",
  "All listed divisions": "তালিকাভুক্ত সব বিভাগ",
  "All specialties": "সব বিশেষত্ব",
  "Allow Med.ai notifications and try again.":
      "Med.ai নোটিফিকেশনের অনুমতি দিয়ে আবার চেষ্টা করুন।",
  "Allow Med.ai to add only these reviewed products and quantities. I will review checkout and pay manually.":
      "শুধু যাচাই করা এই পণ্য ও পরিমাণ কার্টে যোগ করতে অনুমতি দিচ্ছি। চেকআউট যাচাই ও অর্থ প্রদান নিজে করব।",
  "Allow and send": "অনুমতি দিয়ে পাঠান",
  "Allow sharing pickup details with a matching partner":
      "মিলে যাওয়া সেবাদাতার সঙ্গে পিকআপের তথ্য ভাগ করতে সম্মতি দিন",
  "Already have your medicines? Set alarms →": "ওষুধ কেনা আছে? অ্যালার্ম দিন →",
  "Already purchased": "কেনা হয়েছে",
  "Alternatives are unavailable. Sync the prescription and try again.":
      "বিকল্প পাওয়া যাচ্ছে না। প্রেসক্রিপশন সিঙ্ক করে আবার চেষ্টা করুন।",
  "Ambulance GPS · last received {value} · no road ETA.":
      "অ্যাম্বুলেন্স জিপিএস · সর্বশেষ {value} · সড়কপথে পৌঁছানোর সময় জানা নেই।",
  "Ambulance: ": "অ্যাম্বুলেন্স: ",
  "An accepted assignment requires confirmation from the partner.":
      "গৃহীত দায়িত্ব বাতিলে সেবাদাতার নিশ্চিতকরণ প্রয়োজন।",
  "An estimate is incomplete while a medicine has no confirmed price. Unknown prices are never treated as free.":
      "কোনো ওষুধের নিশ্চিত দাম না থাকলে হিসাব অসম্পূর্ণ। অজানা দামকে বিনামূল্যে ধরা হয় না।",
  "An exact, current Arogga product match is required for cart assistance.":
      "কার্ট সহায়তার জন্য Arogga-তে সঠিক ও হালনাগাদ পণ্য মিলতে হবে।",
  "Another matching partner is reviewing your request. No ambulance is confirmed yet.":
      "অন্য একটি উপযুক্ত সেবাদাতা অনুরোধ দেখছেন। এখনো অ্যাম্বুলেন্স নিশ্চিত হয়নি।",
  "Answer language": "উত্তরের ভাষা",
  "App Guide": "অ্যাপ নির্দেশিকা",
  "App Guide is currently unavailable.":
      "অ্যাপ নির্দেশিকা এখন পাওয়া যাচ্ছে না।",
  "Apply selected prices": "নির্বাচিত দাম ব্যবহার করুন",
  "Appointment": "অ্যাপয়েন্টমেন্ট",
  "Approval status was checked when this source was opened, or at the displayed offline download time. Team review is not a diagnosis or an endorsement by the source publisher.":
      "উৎস খোলার সময় বা দেখানো অফলাইন ডাউনলোডের সময় অনুমোদন যাচাই করা হয়েছে। দলের পর্যালোচনা রোগনির্ণয় বা প্রকাশকের সমর্থন নয়।",
  "Area or city (optional)": "এলাকা বা শহর (ঐচ্ছিক)",
  "Arogga pack estimate": "Arogga প্যাকেটের হিসাব",
  "Arogga website · Choose your prescribed product, then use the button below. No account credentials are sent to Med.ai.":
      "Arogga ওয়েবসাইট · প্রেসক্রিপশনের পণ্য বেছে নিচের বোতাম চাপুন। লগইনের গোপন তথ্য Med.ai-তে পাঠানো হয় না।",
  "Arogga · item {value}/{value}": "Arogga · পণ্য {value}/{value}",
  "Ask Med.ai": "Med.ai-কে জিজ্ঞাসা করুন",
  "Ask Your Care Team": "চিকিৎসা দলকে জিজ্ঞাসা করুন",
  "Ask about a report, a health reading, or describe your symptoms.":
      "রিপোর্ট বা পরিমাপ নিয়ে প্রশ্ন করুন, অথবা আপনার লক্ষণ লিখুন।",
  "Ask about this report. AI can make mistakes; verify values against the original.":
      "এই রিপোর্ট নিয়ে প্রশ্ন করুন। এআই ভুল করতে পারে; মূল রিপোর্টের সঙ্গে মান যাচাই করুন।",
  "Ask about your saved reports. AI can make mistakes; verify values against the original.":
      "সংরক্ষিত রিপোর্ট নিয়ে প্রশ্ন করুন। এআই ভুল করতে পারে; মূল রিপোর্টের সঙ্গে মান যাচাই করুন।",
  "Auto": "স্বয়ংক্রিয়",
  "Auto language": "স্বয়ংক্রিয় ভাষা",
  "Auto-schedule reminders": "স্বয়ংক্রিয় রিমাইন্ডার",
  "Automated diagnosis, clinical triage, wearable ingestion and AI chat are not enabled in this release.":
      "এই পাতায় উল্লিখিত সেবার বর্তমান অবস্থা সংশ্লিষ্ট বিভাগে দেখুন।",
  "Availability not confirmed": "প্রাপ্যতা নিশ্চিত নয়",
  "Available care features": "উপলব্ধ চিকিৎসা সহায়তা",
  "Back": "ফিরে যান",
  "Bangladesh time": "বাংলাদেশ সময়",
  "Basic": "সাধারণ",
  "Bengali": "বাংলা",
  "Blood group (if known)": "রক্তের গ্রুপ (জানা থাকলে)",
  "Brand alternatives": "বিকল্প ব্র্যান্ড",
  "Breakfast": "সকালের খাবার",
  "Breakfast, lunch and dinner": "সকাল, দুপুর ও রাতের খাবার",
  "Browse doctor directory": "ডাক্তারের তালিকা দেখুন",
  "Browse the doctor directory by specialty and location":
      "বিশেষত্ব ও স্থান অনুযায়ী ডাক্তার খুঁজুন",
  "Budget is below the delivery reserve. No medicine purchase fits until the budget or reserve is adjusted.":
      "বাজেট ডেলিভারির জন্য রাখা টাকার চেয়ে কম। বাজেট বা সংরক্ষিত খরচ পরিবর্তন করুন।",
  "Budget progress": "বাজেটের ব্যবহার",
  "Buy at a Nearby Pharmacy": "কাছের ফার্মেসিতে কিনুন",
  "Buy in person · Find nearby pharmacies":
      "সরাসরি কিনুন · কাছের ফার্মেসি খুঁজুন",
  "Buy {value} whole pack(s) · {value} units supplied":
      "{value}টি পূর্ণ প্যাকেট কিনুন · মোট {value} একক",
  "Calculate Budget": "বাজেটের হিসাব করুন",
  "Call": "ফোন করুন",
  "Call 999": "৯৯৯-এ ফোন করুন",
  "Call 999 if you need urgent help.":
      "জীবন-হুমকির জরুরি সহায়তা প্রয়োজন হলে ৯৯৯-এ ফোন করুন।",
  "Call center": "সেবাকেন্দ্রে ফোন করুন",
  "Call driver: ": "চালককে ফোন: ",
  "Camera": "ক্যামেরা",
  "Cancel": "বাতিল",
  "Cancel queued upload": "অপেক্ষমাণ আপলোড বাতিল করুন",
  "Cancel request": "অনুরোধ বাতিল করুন",
  "Cancel the request?": "অনুরোধ বাতিল করবেন?",
  "Capture an image and enter verified medicine details.":
      "ছবি তুলুন এবং যাচাই করা ওষুধের তথ্য লিখুন।",
  "Care Team Requests": "চিকিৎসা দলের কাছে অনুরোধ",
  "Care Team Responses": "চিকিৎসা দলের উত্তর",
  "Care Team Updates": "চিকিৎসা দলের আপডেট",
  "Cart preparation needs at least one selected, reviewed medicine with a current exact product price, within your budget. Use Review Quantities to resolve the reason shown for each excluded item.":
      "কার্ট তৈরির জন্য বাজেটের মধ্যে অন্তত একটি নির্বাচিত, যাচাই করা ওষুধের হালনাগাদ সঠিক দাম প্রয়োজন। বাদ পড়ার কারণ পরিমাণ পর্যালোচনায় দেখুন।",
  "Center on ambulance": "অ্যাম্বুলেন্সের স্থানে যান",
  "Changes saved locally · waiting to sync":
      "ডিভাইসে সংরক্ষিত · সিঙ্কের অপেক্ষায়",
  "Chat context": "চ্যাটের তথ্য",
  "Chat history": "চ্যাটের ইতিহাস",
  "Check available storage and try again.":
      "ডিভাইসের খালি জায়গা পরীক্ষা করে আবার চেষ্টা করুন।",
  "Check camera/photo permissions in your device settings.":
      "ডিভাইস সেটিংসে ক্যামেরা ও ছবির অনুমতি পরীক্ষা করুন।",
  "Check each field against the original image before saving.":
      "সংরক্ষণের আগে মূল ছবির সঙ্গে প্রতিটি তথ্য মিলিয়ে নিন।",
  "Check nearby partners": "কাছের সেবাদাতা দেখুন",
  "Check phone alarm access": "ফোনের অ্যালার্ম অনুমতি দেখুন",
  "Check pickup": "পিকআপ যাচাই করুন",
  "Check pickup details": "পিকআপের তথ্য যাচাই করুন",
  "Check special instructions": "বিশেষ নির্দেশনা যাচাই করুন",
  "Check that a browser or Google Maps is available.":
      "ব্রাউজার বা Google Maps আছে কি না দেখুন।",
  "Check the Medicine alarms category and alarm volume in Android settings.":
      "Android সেটিংসে ওষুধের অ্যালার্ম বিভাগ ও অ্যালার্মের শব্দের মাত্রা দেখুন।",
  "Check the details against your original report.":
      "মূল রিপোর্টের সঙ্গে তথ্য মিলিয়ে নিন।",
  "Check the prescription": "প্রেসক্রিপশন যাচাই করুন",
  "Check the saved start date and duration with your prescription.":
      "শুরুর তারিখ ও মেয়াদ প্রেসক্রিপশনের সঙ্গে মিলিয়ে নিন।",
  "Check the suggested test and requesting doctor. Leave either blank if you are unsure.":
      "পরীক্ষা ও নির্দেশদাতা চিকিৎসকের নাম যাচাই করুন। নিশ্চিত না হলে ফাঁকা রাখুন।",
  "Checking partner dispatch availability…":
      "সেবাদাতার অ্যাম্বুলেন্স পাঠানোর অবস্থা দেখা হচ্ছে…",
  "Checking the doctor directory…": "ডাক্তারের তালিকা দেখা হচ্ছে…",
  "Choose Documents to Share": "পাঠানোর নথি বেছে নিন",
  "Choose Exact Product": "সঠিক পণ্য বেছে নিন",
  "Choose JPG or PNG": "JPG বা PNG বেছে নিন",
  "Choose a nearby pharmacy for an in-person purchase.":
      "সরাসরি কেনার জন্য কাছের ফার্মেসি বেছে নিন।",
  "Choose a photo containing only the selected field. Try frequency or duration first.":
      "শুধু নির্বাচিত তথ্যের ছবি দিন। প্রথমে বারসংখ্যা বা মেয়াদ চেষ্টা করুন।",
  "Choose a report image. Med.ai will look for the test name.":
      "রিপোর্টের ছবি দিন। Med.ai পরীক্ষার নাম খুঁজবে।",
  "Choose the exact prescribed brand, strength and dosage form. A similar medicine is not an automatic substitute.":
      "প্রেসক্রিপশনের সঠিক ব্র্যান্ড, শক্তি ও ধরন বেছে নিন। দেখতে একই ওষুধকে স্বয়ংক্রিয় বিকল্প ধরা যায় না।",
  "Choose times from your prescribed schedule.":
      "প্রেসক্রিপশনের সময়সূচি অনুযায়ী সময় দিন।",
  "Choose up to 3 reports, or leave blank to search your uploaded reports.":
      "সর্বোচ্চ ৩টি রিপোর্ট বেছে নিন, অথবা সব আপলোড করা রিপোর্টে খুঁজতে ফাঁকা রাখুন।",
  "City or neighbourhood (optional)": "শহর বা এলাকা (ঐচ্ছিক)",
  "Clear": "মুছুন",
  "Clear chat history": "চ্যাটের ইতিহাস মুছুন",
  "Clear chat history?": "চ্যাটের ইতিহাস মুছবেন?",
  "Clear preferred brand": "পছন্দের ব্র্যান্ড সরান",
  "Clear preferred brand?": "পছন্দের ব্র্যান্ড সরাবেন?",
  "Clear report date": "রিপোর্টের তারিখ মুছুন",
  "Clear supplier login/session": "সরবরাহকারীর লগইন মুছুন",
  "Clinic schedule": "ক্লিনিকের সময়সূচি",
  "Close": "বন্ধ করুন",
  "Compare each draft with the image. Edits here are for testing only.":
      "খসড়া মূল ছবির সঙ্গে মিলিয়ে নিন। এখানকার সম্পাদনা শুধু পরীক্ষার জন্য।",
  "Compare ingredient, strength, dosage form and release type. Product listings do not confirm stock. Ask a pharmacist before switching.":
      "উপাদান, শক্তি, ওষুধের ধরন ও মুক্তির ধরন মিলিয়ে নিন। তালিকা মজুত নিশ্চিত করে না। পরিবর্তনের আগে ফার্মাসিস্টের পরামর্শ নিন।",
  "Compare names, strengths and instructions.":
      "নাম, শক্তি ও নির্দেশনা মিলিয়ে নিন।",
  "Confirm": "নিশ্চিত করুন",
  "Confirm ambulance request": "অ্যাম্বুলেন্সের অনুরোধ নিশ্চিত করুন",
  "Confirm by voice": "কথা বলে নিশ্চিত করুন",
  "Confirm medicine details & include": "ওষুধের তথ্য নিশ্চিত করে যোগ করুন",
  "Confirm reminder times": "রিমাইন্ডারের সময় নিশ্চিত করুন",
  "Confirm the SMS code, prescription and order on Arogga. Payment is always manual.":
      "Arogga-তে এসএমএস কোড, প্রেসক্রিপশন ও অর্ডার নিশ্চিত করুন। অর্থ প্রদান সবসময় নিজে করতে হবে।",
  "Confirm the timing": "সময় নিশ্চিত করুন",
  "Confirmation records your review. It is not pharmacist approval and does not change dosing.":
      "নিশ্চিতকরণ আপনার যাচাই নথিবদ্ধ করে। এটি ফার্মাসিস্টের অনুমোদন নয় এবং ডোজ পরিবর্তন করে না।",
  "Confirmed minutes after meals": "খাবারের পরে নিশ্চিত মিনিট",
  "Confirmed minutes before meals": "খাবারের আগে নিশ্চিত মিনিট",
  "Connected Services": "সংযুক্ত সেবা",
  "Continue": "চালিয়ে যান",
  "Continue manually at {value}? Med.ai will not fill payment details or submit an order.":
      "{value}-এ নিজে চালিয়ে যাবেন? Med.ai পেমেন্টের তথ্য পূরণ বা অর্ডার জমা দেবে না।",
  "Continue manually in browser": "ব্রাউজারে নিজে চালিয়ে যান",
  "Conversations": "কথোপকথন",
  "Copied": "কপি হয়েছে",
  "Copy a JSON export to your clipboard.": "JSON রেকর্ড ক্লিপবোর্ডে কপি করুন।",
  "Copy the exact number and unit from the original lab report.":
      "মূল ল্যাব রিপোর্টের সঠিক সংখ্যা ও একক লিখুন।",
  "Could not access image": "ছবি খোলা যায়নি",
  "Could not load care-team updates. Connect and refresh.":
      "চিকিৎসা দলের আপডেট আসেনি। সংযোগ দিয়ে রিফ্রেশ করুন।",
  "Could not load this image. Connect to the server and try again.":
      "ছবি আসেনি। সার্ভারে সংযোগ দিয়ে আবার চেষ্টা করুন।",
  "Could not open Maps": "মানচিত্র খোলা যায়নি",
  "Could not open maps": "মানচিত্র খোলা যায়নি",
  "Could not open source": "উৎস খোলা যায়নি",
  "Could not open the clinic link.": "ক্লিনিকের লিংক খোলা যায়নি।",
  "Could not open the dialer. Clinic number: {value}":
      "ডায়ালার খোলা যায়নি। ক্লিনিকের নম্বর: {value}",
  "Could not play alarm": "অ্যালার্ম বাজানো যায়নি",
  "Could not reload": "আবার লোড করা যায়নি",
  "Could not remove": "সরানো যায়নি",
  "Could not save": "সংরক্ষণ করা যায়নি",
  "Could not save document": "নথি সংরক্ষণ করা যায়নি",
  "Could not save meal times": "খাবারের সময় সংরক্ষণ করা যায়নি",
  "Could not save report details": "রিপোর্টের তথ্য সংরক্ষণ করা যায়নি",
  "Could not schedule": "সময়সূচি তৈরি করা যায়নি",
  "Could not sign out": "সাইন আউট করা যায়নি",
  "Could not update supply": "মজুত হালনাগাদ করা যায়নি",
  "Could not withdraw": "প্রত্যাহার করা যায়নি",
  "Course and supply": "কোর্স ও মজুত",
  "Course has ended": "কোর্সের মেয়াদ শেষ",
  "Course start: today (tap to change)": "কোর্স শুরু: আজ (বদলাতে চাপুন)",
  "Course start: {value}": "কোর্স শুরু: {value}",
  "Course total: {value} · Units logged: {value}":
      "কোর্সে মোট: {value} · গ্রহণ নথিভুক্ত: {value}",
  "Create Account": "অ্যাকাউন্ট তৈরি করুন",
  "Create Your Account": "আপনার অ্যাকাউন্ট তৈরি করুন",
  "Create your medicine list first.": "আগে ওষুধের তালিকা তৈরি করুন।",
  "Delete": "মুছুন",
  "Delete conversation": "কথোপকথন মুছুন",
  "Delete this conversation?": "কথোপকথন মুছবেন?",
  "Delivery is a reserve you enter, not a supplier shipping quote. Final charges are shown on Arogga.":
      "ডেলিভারির জন্য আপনি টাকা রাখছেন; এটি সরবরাহকারীর নিশ্চিত খরচ নয়। চূড়ান্ত খরচ Arogga-তে দেখুন।",
  "Delivery reserve (BDT)": "ডেলিভারির জন্য রাখা টাকা",
  "Details correct — include": "তথ্য সঠিক — যোগ করুন",
  "Dial 999 using your phone app.": "ফোনের ডায়ালারে ৯৯৯ লিখুন।",
  "Dictate symptoms": "লক্ষণ বলুন",
  "Dinner": "রাতের খাবার",
  "Directions": "যাওয়ার পথ",
  "Directory listings do not confirm appointment availability.":
      "তালিকায় থাকা মানেই অ্যাপয়েন্টমেন্ট পাওয়া নিশ্চিত নয়।",
  "Directory unavailable. Retry": "তালিকা পাওয়া যাচ্ছে না। আবার চেষ্টা করুন",
  "Discuss statistics in AI Chat": "এআই চ্যাটে পরিসংখ্যান নিয়ে আলোচনা করুন",
  "Do not wait for this request if you need urgent help.":
      "জরুরি সহায়তার প্রয়োজন হলে এই অনুরোধের অপেক্ষা করবেন না।",
  "Doctor profile": "ডাক্তারের পরিচিতি",
  "Doctor search location": "ডাক্তার খোঁজার এলাকা",
  "Doctors": "ডাক্তার",
  "Document": "নথি",
  "Document category": "নথির বিভাগ",
  "Document review": "নথি পর্যালোচনা",
  "Done": "সম্পন্ন",
  "Dosage form": "ওষুধের ধরন",
  "Dose logged · {value}": "ডোজ নথিভুক্ত · {value}",
  "Dose not saved": "ডোজ সংরক্ষিত হয়নি",
  "Download the approved library to encrypted device storage for up to 24 hours. Individual source review dates may expire sooner.":
      "অনুমোদিত তথ্যভান্ডার সর্বোচ্চ ২৪ ঘণ্টা এনক্রিপ্ট করা ডিভাইসে রাখুন। কোনো উৎসের পর্যালোচনার মেয়াদ আগেই শেষ হতে পারে।",
  "Downloaded copy. Current approval or withdrawal status cannot be confirmed offline.":
      "ডাউনলোড করা কপি। অফলাইনে বর্তমান অনুমোদন বা প্রত্যাহারের অবস্থা নিশ্চিত করা যায় না।",
  "Duration": "মেয়াদ",
  "Edit meal times": "খাবারের সময় পরিবর্তন করুন",
  "Edit medicine": "ওষুধ সম্পাদনা করুন",
  "Edit prescription details": "প্রেসক্রিপশনের তথ্য সম্পাদনা করুন",
  "Emergency Ambulance": "জরুরি অ্যাম্বুলেন্স",
  "Emergency contact, blood group and private uploads.":
      "জরুরি যোগাযোগ, রক্তের গ্রুপ ও ব্যক্তিগত নথি।",
  "Emergency details (optional)": "জরুরি অবস্থার বিবরণ (ঐচ্ছিক)",
  "Enable notifications in your device settings, then schedule again.":
      "ডিভাইস সেটিংসে নোটিফিকেশন চালু করে আবার সময়সূচি দিন।",
  "English": "English",
  "Enter Medicine from This Document": "এই নথি থেকে ওষুধ লিখুন",
  "Enter lab value": "ল্যাব পরীক্ষার মান লিখুন",
  "Enter manually": "নিজে লিখুন",
  "Enter only what your prescription says.":
      "শুধু প্রেসক্রিপশনে যা লেখা আছে তা লিখুন।",
  "Enter or correct pickup coordinates": "পিকআপের স্থানাঙ্ক লিখুন বা ঠিক করুন",
  "Enter the prescribed duration": "প্রেসক্রিপশনের মেয়াদ লিখুন",
  "Enter value from report": "রিপোর্ট থেকে মান লিখুন",
  "Estimates expire after 24 hours. The supplier may change its price or availability before checkout.":
      "হিসাবের মেয়াদ ২৪ ঘণ্টা। চেকআউটের আগে সরবরাহকারী দাম বা প্রাপ্যতা বদলাতে পারেন।",
  "Exact source passages with visible citations.":
      "উৎসের সঠিক অংশ ও তথ্যসূত্র।",
  "Example: 1 if prescribed one tablet each time":
      "উদাহরণ: প্রতিবার একটি ট্যাবলেট লেখা থাকলে 1",
  "Explore Med.ai": "Med.ai-এর সেবাগুলো দেখুন",
  "Explore pharmacies and clinics in Google Maps.":
      "Google Maps-এ ফার্মেসি ও ক্লিনিক দেখুন।",
  "Export Local Record": "ডিভাইসের রেকর্ড রপ্তানি করুন",
  "Field": "তথ্যের ঘর",
  "Fill / Resume Cart": "কার্ট পূরণ / চালিয়ে যান",
  "Filter by division": "বিভাগ অনুযায়ী বাছাই করুন",
  "Find Care Near You": "কাছের চিকিৎসাসেবা খুঁজুন",
  "Find Clinics and Hospitals": "ক্লিনিক ও হাসপাতাল খুঁজুন",
  "Find Exact Product & Price": "সঠিক পণ্য ও দাম খুঁজুন",
  "Find Near My Location": "আমার অবস্থানের কাছে খুঁজুন",
  "Find Nearby Pharmacies": "কাছের ফার্মেসি খুঁজুন",
  "Find a doctor": "ডাক্তার খুঁজুন",
  "Find matching doctors": "প্রাসঙ্গিক ডাক্তার খুঁজুন",
  "Find reports by test name, date, or doctor.":
      "পরীক্ষার নাম, তারিখ বা চিকিৎসক দিয়ে রিপোর্ট খুঁজুন।",
  "Finding brand alternatives": "বিকল্প ব্র্যান্ড খোঁজা",
  "For calculation, enter a fixed frequency and the prescribed units per dose.":
      "হিসাবের জন্য নির্দিষ্ট বারসংখ্যা ও প্রতি ডোজের পরিমাণ লিখুন।",
  "For urgent help in Bangladesh, call 999. Do not wait for an unanswered app request.":
      "বাংলাদেশে জরুরি সহায়তার জন্য ৯৯৯-এ ফোন করুন। উত্তর না আসা অ্যাপের অনুরোধের অপেক্ষা করবেন না।",
  "Frequency as prescribed": "প্রেসক্রিপশন অনুযায়ী বারসংখ্যা",
  "Full name": "পুরো নাম",
  "Full prescription": "সম্পূর্ণ প্রেসক্রিপশন",
  "GPS precision is low. Check the pin or correct the coordinates.":
      "জিপিএসের নির্ভুলতা কম। পিন যাচাই করুন বা স্থানাঙ্ক ঠিক করুন।",
  "Gallery": "গ্যালারি",
  "Get Started": "শুরু করুন",
  "Getting GPS…": "জিপিএস অবস্থান নেওয়া হচ্ছে…",
  "Google Voice (or your Android speech service) handles dictation and may process audio online. Review the transcript before sending.":
      "Google Voice বা Android-এর ভয়েস সেবা অনলাইনে অডিও প্রক্রিয়াকরণ করতে পারে। পাঠানোর আগে লেখা যাচাই করুন।",
  "Got it": "বুঝেছি",
  "Groq processes your question, recent chat and relevant report text. Text can contain personal information. Original images stay on your Med.ai server. AI can make mistakes; verify report values. Use fictional reports for initial testing.":
      "চ্যাটে ব্যবহৃত তথ্যের অনুমতি যাচাই করুন। মূল রিপোর্টের সঙ্গে মান মিলিয়ে নিন এবং প্রাথমিক পরীক্ষায় কাল্পনিক তথ্য ব্যবহার করুন।",
  "Health context on": "স্বাস্থ্যতথ্য ব্যবহার চালু",
  "Health context on · synced records only":
      "স্বাস্থ্যতথ্য ব্যবহার চালু · শুধু সিঙ্ক করা রেকর্ড",
  "Health measurements": "স্বাস্থ্যের পরিমাপ",
  "Hello, {value}": "স্বাগতম, {value}",
  "Hide password": "পাসওয়ার্ড লুকান",
  "Hours not listed": "সময় উল্লেখ নেই",
  "How can I help?": "কীভাবে সাহায্য করতে পারি?",
  "I agree to share my saved profile, medicines, measurements, dose logs and selected documents with clinicians in this Med.ai care team.":
      "এই Med.ai চিকিৎসা দলের সঙ্গে সংরক্ষিত প্রোফাইল, ওষুধ, পরিমাপ, ডোজের ইতিহাস ও নির্বাচিত নথি ভাগ করতে সম্মতি দিচ্ছি।",
  "I checked the brand, strength, form and pack. My prescribed quantity ({value}) is in individual {value} units, not packs.":
      "ব্র্যান্ড, শক্তি, ধরন ও প্যাকেট যাচাই করেছি। প্রেসক্রিপশনের পরিমাণ ({value}) আলাদা {value} এককে, প্যাকেট নয়।",
  "I checked these fields against the prescription.":
      "প্রেসক্রিপশনের সঙ্গে এই তথ্য মিলিয়ে নিয়েছি।",
  "I understand which medicines are excluded. This does not mark their details as reviewed or change my prescription.":
      "কোন ওষুধ বাদ পড়েছে বুঝেছি। এতে ওষুধের তথ্য যাচাই হয়েছে ধরা হবে না বা প্রেসক্রিপশন বদলাবে না।",
  "Identity": "পরিচয়পত্র",
  "If needed, allow Alarms & reminders in Android settings. This button only manages access.":
      "প্রয়োজনে Android সেটিংসে অ্যালার্ম ও রিমাইন্ডারের অনুমতি দিন। এই বোতাম শুধু অনুমতি পরিচালনা করে।",
  "Included": "অন্তর্ভুক্ত",
  "Incomplete prescription basket. Review excluded items with your pharmacist.":
      "প্রেসক্রিপশনের কার্ট অসম্পূর্ণ। বাদ পড়া ওষুধ নিয়ে ফার্মাসিস্টের সঙ্গে আলোচনা করুন।",
  "Individual-unit budget estimate": "খুচরা এককে বাজেটের হিসাব",
  "Individually affordable: {value} / {value} units to buy. Cost comparison only.":
      "সামর্থ্য অনুযায়ী: {value} / {value} একক। শুধু খরচের তুলনা।",
  "Insurance": "বিমা",
  "Intake history is full": "ওষুধ গ্রহণের ইতিহাস পূর্ণ",
  "Items to review on Arogga": "Arogga-তে যাচাই করার পণ্য",
  "Keep": "রাখুন",
  "Keep local data": "ডিভাইসের তথ্য রাখুন",
  "Keep reminders; exclude from the shopping budget.":
      "রিমাইন্ডার রাখুন; কেনাকাটার বাজেট থেকে বাদ দিন।",
  "Keep request": "অনুরোধ রাখুন",
  "Keep your care information up to date.":
      "আপনার স্বাস্থ্যতথ্য হালনাগাদ রাখুন।",
  "Known allergies (leave blank if not recorded)":
      "জানা অ্যালার্জি (নথিভুক্ত না থাকলে ফাঁকা রাখুন)",
  "Known ambulance category (optional)":
      "প্রয়োজনীয় অ্যাম্বুলেন্সের ধরন (ঐচ্ছিক)",
  "Known equipment needs (optional)": "জানা সরঞ্জামের প্রয়োজন (ঐচ্ছিক)",
  "LOCAL SANDBOX · Use fictional details only. No real ambulance, calls or SMS.":
      "স্থানীয় পরীক্ষামূলক পরিবেশ · শুধু কাল্পনিক তথ্য দিন। প্রকৃত অ্যাম্বুলেন্স, কল বা এসএমএস নয়।",
  "Lab Report": "ল্যাব রিপোর্ট",
  "Lab report trends": "ল্যাব রিপোর্টের প্রবণতা",
  "Lab reports": "ল্যাব রিপোর্ট",
  "Last checked: {value}": "সর্বশেষ দেখা হয়েছে: {value}",
  "Last recorded {value}": "সর্বশেষ নথিভুক্ত {value}",
  "Listed in stock": "তালিকায় মজুত আছে",
  "Listed unavailable": "তালিকায় পাওয়া যাচ্ছে না",
  "Live partner dispatch has not been enabled on this server. For urgent help, call 999.":
      "এই সার্ভারে সেবাদাতার লাইভ অ্যাম্বুলেন্স প্রেরণ চালু নেই। জরুরি সহায়তা প্রয়োজন হলে ৯৯৯-এ ফোন করুন।",
  "Live position unavailable. The driver may not be sharing or the last update expired.":
      "লাইভ অবস্থান নেই। চালক অবস্থান না-ও পাঠাতে পারেন বা সর্বশেষ তথ্য পুরোনো হয়েছে।",
  "Load profile": "প্রোফাইল আনুন",
  "Location is {value} minute(s) old, estimated accuracy {value} m. Search around it?":
      "অবস্থান {value} মিনিট আগের; আনুমানিক নির্ভুলতা {value} মিটার। এর কাছে খুঁজবেন?",
  "Log In": "লগইন করুন",
  "Log dose taken": "গ্রহণ করা ডোজ লিখুন",
  "Low supply": "মজুত কম",
  "Lunch": "দুপুরের খাবার",
  "Manage phone alarm permissions": "ফোনের অ্যালার্মের অনুমতি",
  "Manage readings": "পরিমাপ পরিচালনা করুন",
  "Manual": "নিজে লিখুন",
  "Mark taken": "খাওয়া হয়েছে",
  "Match Online Price": "অনলাইন দাম মিলিয়ে নিন",
  "Match an exact product to fetch its current price.":
      "বর্তমান দাম জানতে সঠিক পণ্য মিলিয়ে নিন।",
  "Matching doctors": "প্রাসঙ্গিক ডাক্তার",
  "Meal and interval instructions could not be combined safely. Set a confirmed meal offset or enter the prescribed times in Reminders.":
      "খাবার ও বিরতির নির্দেশনা নিরাপদে এক করা যায়নি। নিশ্চিত খাবারের ব্যবধান দিন অথবা নিজে নির্ধারিত সময় লিখুন।",
  "Meal times and offsets": "খাবারের সময় ও ব্যবধান",
  "Meal times saved. Allow notifications and tap Save and Schedule in Medicine Reminders.":
      "খাবারের সময় সংরক্ষিত। নোটিফিকেশনের অনুমতি দিয়ে ওষুধের রিমাইন্ডারে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Meal times saved. Open Medicine Reminders and tap Save and Schedule to retry the phone update.":
      "খাবারের সময় সংরক্ষিত। ফোনে আবার প্রয়োগ করতে ওষুধের রিমাইন্ডারে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Meal times saved. {value} reminder times updated or added.":
      "খাবারের সময় সংরক্ষিত। {value}টি রিমাইন্ডারের সময় যোগ বা হালনাগাদ হয়েছে।",
  "Meal timing": "খাবারের সঙ্গে সময়",
  "Measurement type": "পরিমাপের ধরন",
  "Measurements": "পরিমাপ",
  "Measurements you enter from your own devices.":
      "আপনার যন্ত্রে মাপা মান নিজে লিখুন।",
  "Med.ai App Guide": "Med.ai অ্যাপ নির্দেশিকা",
  "Med.ai Assistant": "Med.ai সহকারী",
  "Med.ai could not read an exact fixed frequency. Check the prescription, or open Reminders to choose the prescribed times yourself.":
      "নির্দিষ্ট বারসংখ্যা বোঝা যায়নি। প্রেসক্রিপশন যাচাই করুন বা নিজে রিমাইন্ডারের সময় দিন।",
  "Med.ai processes your records on its own server. Optional AI definitions use a fixed public glossary, without sending your messages or reports.":
      "Med.ai নিজস্ব সার্ভারে রেকর্ড প্রক্রিয়াকরণ করে। ঐচ্ছিক এআই সংজ্ঞার জন্য শুধু নির্দিষ্ট সাধারণ শব্দতালিকা পাঠানো হয়; আপনার বার্তা বা রিপোর্ট পাঠানো হয় না।",
  "Medical": "চিকিৎসাসংক্রান্ত",
  "Medical Documents": "চিকিৎসার নথি",
  "Medication Activity": "ওষুধের কার্যক্রম",
  "Medication Details": "ওষুধের বিবরণ",
  "Medicine": "ওষুধ",
  "Medicine Reminders": "ওষুধের রিমাইন্ডার",
  "Medicine name": "ওষুধের নাম",
  "Medicine not found": "ওষুধ পাওয়া যায়নি",
  "Medicine schedule": "ওষুধের সময়সূচি",
  "Medicines found": "পাওয়া ওষুধ",
  "Message / আপনার প্রশ্ন": "আপনার প্রশ্ন",
  "Mixed English + Bengali": "ইংরেজি ও বাংলা মিশ্রিত",
  "Most recent {value} readings in the same unit, in date order.":
      "একই এককে সর্বশেষ {value}টি পরিমাপ, তারিখের ক্রমে।",
  "My Health Overview": "আমার স্বাস্থ্যের সারসংক্ষেপ",
  "Nearby Pharmacies": "কাছের ফার্মেসি",
  "Need help signing in?": "লগইনে সাহায্য দরকার?",
  "Need to buy": "কিনতে হবে",
  "Needs review": "যাচাই প্রয়োজন",
  "Needs your review": "আপনার যাচাই প্রয়োজন",
  "Neonatal": "নবজাতকের জন্য",
  "New chat": "নতুন চ্যাট",
  "Next product (manual)": "পরের পণ্য (নিজে)",
  "No OCR text yet": "এখনো ছবি থেকে লেখা আসেনি",
  "No additional purchase needed": "আর কেনার প্রয়োজন নেই",
  "No ambulance confirmed": "অ্যাম্বুলেন্স নিশ্চিত হয়নি",
  "No ambulance is confirmed.": "কোনো অ্যাম্বুলেন্স নিশ্চিত হয়নি।",
  "No chartable values from synced report text yet. Upload a clear lab report and refresh.":
      "সিঙ্ক করা রিপোর্ট থেকে চার্টের উপযোগী মান নেই। পরিষ্কার রিপোর্ট দিয়ে রিফ্রেশ করুন।",
  "No date listed": "তারিখ উল্লেখ নেই",
  "No directory matches in the selected area.":
      "নির্বাচিত এলাকায় তালিকায় মিল নেই।",
  "No doctor listed": "ডাক্তার উল্লেখ নেই",
  "No doses recorded yet.": "এখনো কোনো ডোজ লেখা হয়নি।",
  "No eligible medicines": "উপযুক্ত ওষুধ নেই",
  "No entries": "কোনো তথ্য নেই",
  "No fixed course total. Enter the quantity prescribed for this refill.":
      "নির্দিষ্ট কোর্সের মোট পরিমাণ নেই। এইবারের জন্য প্রেসক্রিপশনে লেখা পরিমাণ দিন।",
  "No linked document": "সংযুক্ত নথি নেই",
  "No listed doctors match this specialty and division. You can widen the search.":
      "এই বিশেষত্ব ও এলাকায় ডাক্তার মেলেনি। খোঁজার পরিসর বাড়াতে পারেন।",
  "No medicines in this section.": "এই বিভাগে ওষুধ নেই।",
  "No medicines yet. Add an item from your prescription.":
      "এখনো ওষুধ নেই। প্রেসক্রিপশন থেকে যোগ করুন।",
  "No offline copy is saved. Download while connected.":
      "অফলাইন কপি নেই। সংযোগ থাকলে ডাউনলোড করুন।",
  "No pharmacies were mapped in this search area. Coverage may be incomplete; try Google Maps below.":
      "এই এলাকায় মানচিত্রে ফার্মেসি পাওয়া যায়নি। তথ্য অসম্পূর্ণ হতে পারে; নিচে Google Maps চেষ্টা করুন।",
  "No preference": "নির্দিষ্ট পছন্দ নেই",
  "No prices updated": "কোনো দাম হালনাগাদ হয়নি",
  "No purchase needed": "কিনতে হবে না",
  "No readable medicines were returned. Use the image to enter details manually.":
      "পড়ার উপযোগী ওষুধের তথ্য পাওয়া যায়নি। ছবি দেখে নিজে লিখুন।",
  "No readings recorded": "পরিমাপ লেখা হয়নি",
  "No readings yet": "এখনো পরিমাপ নেই",
  "No reports match your search.": "খোঁজার সঙ্গে কোনো রিপোর্ট মেলেনি।",
  "No request sent": "অনুরোধ পাঠানো হয়নি",
  "No review requests yet.": "এখনো পর্যালোচনার অনুরোধ নেই।",
  "No verified partner online nearby":
      "কাছে যাচাই করা কোনো সেবাদাতা অনলাইনে নেই",
  "Not Included": "অন্তর্ভুক্ত নয়",
  "Not affordable in this estimate.": "এই হিসাবে বাজেটের মধ্যে পড়ে না।",
  "Not complete": "অসম্পূর্ণ",
  "Not confirmed. Say “confirm ambulance” or tap Send request.":
      "নিশ্চিত হয়নি। “confirm ambulance” বলুন বা অনুরোধ পাঠান চাপুন।",
  "Not now": "এখন নয়",
  "Not recorded": "নথিভুক্ত নয়",
  "Nothing scheduled": "সময়সূচি নেই",
  "Notification permission needed": "নোটিফিকেশনের অনুমতি প্রয়োজন",
  "Notifications": "নোটিফিকেশন",
  "OCR did not find values with supported units":
      "ছবি থেকে সমর্থিত এককের মান পাওয়া যায়নি",
  "OCR is unavailable or produced no text. Your document is still saved.":
      "ছবি থেকে লেখা পড়া যায়নি বা সেবা নেই। নথি সংরক্ষিত আছে।",
  "OCR language": "ছবির লেখার ভাষা",
  "OCR text needs careful review, especially handwriting and medicine names.":
      "ছবি থেকে পড়া লেখা, বিশেষ করে হাতের লেখা ও ওষুধের নাম, ভালোভাবে যাচাই করুন।",
  "Offline Reading": "অফলাইনে পড়া",
  "Offline copy": "অফলাইন কপি",
  "Offline copy · last checked {value}": "অফলাইন কপি · সর্বশেষ যাচাই {value}",
  "{value} {value}. Withdrawals cannot be rechecked while offline.":
      "{value} {value}। অফলাইনে প্রত্যাহারের অবস্থা আবার যাচাই করা যায় না।",
  "On hand: {value} · To buy: {value}": "মজুত: {value} · কিনতে হবে: {value}",
  "One field (already cropped)": "একটি তথ্য (কাটা ছবি)",
  "One partner at a time. If they cannot respond, another matching partner may receive the request.":
      "একবারে একজন সেবাদাতা। সাড়া না পেলে অন্য উপযুক্ত সেবাদাতা অনুরোধ পেতে পারেন।",
  "Only clearly recognized values with units are plotted. Verify them against the original report. Different units are charted separately.":
      "শুধু স্পষ্টভাবে পড়া এককসহ মান চার্টে দেখানো হয়। মূল রিপোর্টের সঙ্গে মিলিয়ে নিন। আলাদা এককের আলাদা চার্ট।",
  "Only complete prescribed quantities are selected automatically. Individual affordability is not a dosing recommendation.":
      "শুধু প্রেসক্রিপশনের সম্পূর্ণ পরিমাণ স্বয়ংক্রিয়ভাবে নির্বাচিত হয়। কেনার সামর্থ্য ডোজের পরামর্শ নয়।",
  "Open": "খুলুন",
  "Open Android Settings → Apps → Special access → Alarms & reminders. Then return and tap Save and Schedule.":
      "Android সেটিংস → অ্যাপস → বিশেষ অনুমতি → অ্যালার্ম ও রিমাইন্ডার খুলুন। ফিরে এসে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Open Google Maps": "Google Maps খুলুন",
  "Open Google Maps and search for pharmacies in your area.":
      "Google Maps খুলে আপনার এলাকায় ফার্মেসি খুঁজুন।",
  "Open Original Source": "মূল উৎস খুলুন",
  "Open Reports": "রিপোর্ট খুলুন",
  "Open Supplier Cart · checkout manually":
      "সরবরাহকারীর কার্ট খুলুন · চেকআউট নিজে করুন",
  "Open clinic appointment page": "ক্লিনিকের অ্যাপয়েন্টমেন্ট পাতা খুলুন",
  "Open dialer for 999 (Bangladesh)": "৯৯৯-এর ডায়ালার খুলুন (বাংলাদেশ)",
  "Open external page?": "বাইরের ওয়েবপাতা খুলবেন?",
  "Open listing source": "তালিকার উৎস খুলুন",
  "Open location permissions": "অবস্থানের অনুমতি খুলুন",
  "Open location service settings": "অবস্থানের সেটিংস খুলুন",
  "Open medicine list →": "ওষুধের তালিকা খুলুন →",
  "Open or dismiss the alert to stop the sound. Choose reminder times from the prescription, then tap Save and Schedule on this phone.":
      "শব্দ থামাতে অ্যালার্ট খুলুন বা বন্ধ করুন। প্রেসক্রিপশন অনুযায়ী সময় দিয়ে এই ফোনে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Open {value} medicines": "{value}টি ওষুধ দেখুন",
  "Optional question": "ঐচ্ছিক প্রশ্ন",
  "Optional report selection": "রিপোর্ট বাছাই (ঐচ্ছিক)",
  "Original report": "মূল রিপোর্ট",
  "Other": "অন্যান্য",
  "PDF, JPEG or PNG, up to 8 MB each. These files are not added to AI Chat.":
      "PDF, JPEG বা PNG; প্রতিটি সর্বোচ্চ ৮ মেগাবাইট। এগুলো এআই চ্যাটে যোগ হয় না।",
  "Password reset and email verification are not configured yet. Contact your project administrator for account recovery.":
      "পাসওয়ার্ড পুনরুদ্ধার ও ইমেইল যাচাই এখনো সেটআপ করা নেই। অ্যাকাউন্ট ফেরত পেতে প্রকল্প পরিচালকের সঙ্গে যোগাযোগ করুন।",
  "Pending · Mark taken": "বাকি · খাওয়া হয়েছে চিহ্ন দিন",
  "Personal details and documents": "ব্যক্তিগত তথ্য ও নথি",
  "Phone": "ফোন",
  "Phone alarm permission is on. Tap Save and Schedule to apply your reminder changes.":
      "অ্যালার্মের অনুমতি চালু আছে। পরিবর্তন প্রয়োগ করতে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Pickup and ambulance location": "পিকআপ ও অ্যাম্বুলেন্সের অবস্থান",
  "Pickup contact number": "পিকআপ যোগাযোগের নম্বর",
  "Pickup location": "পিকআপ স্থান",
  "Pickup: ": "পিকআপ: ",
  "Preferred": "পছন্দের",
  "Prepare Cart on Arogga": "Arogga-তে কার্ট তৈরি করুন",
  "Prescribed: {value} {value} · {value}":
      "প্রেসক্রিপশনে: {value} {value} · {value}",
  "Prescription": "প্রেসক্রিপশন",
  "Prescription OCR test": "প্রেসক্রিপশনের লেখা পড়ার পরীক্ষা",
  "Price needed": "দাম প্রয়োজন",
  "Prices & Budget": "দাম ও বাজেট",
  "Prices include whole sales packs. Any extra units are packaging surplus, not an instruction to take more medicine.":
      "দাম পূর্ণ প্যাকেটের হিসাবে। বাড়তি ওষুধ প্যাকেটের অতিরিক্ত অংশ, বেশি ওষুধ খাওয়ার নির্দেশনা নয়।",
  "Private documents": "ব্যক্তিগত নথি",
  "Private to your Med.ai account.": "শুধু আপনার Med.ai অ্যাকাউন্টের জন্য।",
  "Profile details saved.": "প্রোফাইলের তথ্য সংরক্ষিত।",
  "Profile saved": "প্রোফাইল সংরক্ষিত",
  "Purchase estimate · BDT · prescribed instructions stay unchanged.":
      "কেনার আনুমানিক খরচ · টাকা · প্রেসক্রিপশনের নির্দেশনা অপরিবর্তিত।",
  "Quantity for this prescription or refill":
      "এই প্রেসক্রিপশন বা পুনরায় কেনার পরিমাণ",
  "Queued for upload": "আপলোডের অপেক্ষায়",
  "Queued on this device": "এই ডিভাইসে অপেক্ষমাণ",
  "Read / Review Prescription": "প্রেসক্রিপশন পড়ুন / যাচাই করুন",
  "Read source details ›": "উৎসের বিবরণ পড়ুন ›",
  "Reading…": "পড়া হচ্ছে…",
  "Recent dated reports, in sequence": "তারিখ অনুযায়ী সাম্প্রতিক রিপোর্ট",
  "Recognized Text": "পড়া লেখা",
  "Recommended department · routine consultation":
      "প্রস্তাবিত বিভাগ · সাধারণ পরামর্শ",
  "Record purchase": "কেনা ওষুধ লিখুন",
  "Record readings from your own measurement devices.":
      "আপনার যন্ত্রে মাপা মান লিখুন।",
  "Recorded Measurements": "সংরক্ষিত পরিমাপ",
  "Recorded {value} · {value} readings": "সংরক্ষিত {value} · {value}টি পরিমাপ",
  "Records are encrypted on your device and server.":
      "আপনার ডিভাইস ও সার্ভারে রেকর্ড এনক্রিপ্ট করা থাকে।",
  "Reference Details": "তথ্যসূত্রের বিবরণ",
  "Refill level": "পুনরায় কেনার সীমা",
  "Refresh": "রিফ্রেশ করুন",
  "Refresh Offline Copy": "অফলাইন কপি হালনাগাদ করুন",
  "Refresh Statistics": "পরিসংখ্যান হালনাগাদ করুন",
  "Refresh history": "ইতিহাস হালনাগাদ করুন",
  "Refresh status": "অবস্থা হালনাগাদ করুন",
  "Refresh to check results": "ফল দেখতে রিফ্রেশ করুন",
  "Refreshing…": "হালনাগাদ হচ্ছে…",
  "Relevant doctors": "প্রাসঙ্গিক ডাক্তার",
  "Reload server record": "সার্ভারের রেকর্ড আনুন",
  "Reload the server record?": "সার্ভারের রেকর্ড আবার আনবেন?",
  "Reminder already set": "রিমাইন্ডার আগে থেকেই আছে",
  "Reminder limit": "রিমাইন্ডারের সীমা",
  "Reminders are scheduled in {value}. {value}":
      "রিমাইন্ডারের সময় অঞ্চল {value}। {value}",
  "Reminders saved. Enable notifications to receive them.":
      "রিমাইন্ডার সংরক্ষিত। পেতে নোটিফিকেশন চালু করুন।",
  "Reminders scheduled": "রিমাইন্ডারের সময়সূচি তৈরি হয়েছে",
  "Remove": "সরান",
  "Remove attachment": "সংযুক্তি সরান",
  "Remove attachment?": "সংযুক্তি সরাবেন?",
  "Remove downloaded copy": "ডাউনলোড করা কপি সরান",
  "Remove from medicine list": "ওষুধের তালিকা থেকে সরান",
  "Remove queued document?": "অপেক্ষমাণ নথি সরাবেন?",
  "Remove reminder": "রিমাইন্ডার সরান",
  "Remove this medicine?": "এই ওষুধ সরাবেন?",
  "Remove unused reminders and try again.":
      "অব্যবহৃত রিমাইন্ডার সরিয়ে আবার চেষ্টা করুন।",
  "Replaces the online quote; manual prices do not enable cart assistance.":
      "অনলাইন দামের বদলে ব্যবহার হবে; নিজের লেখা দাম দিয়ে কার্ট সহায়তা চালু হয় না।",
  "Report assistant": "রিপোর্ট সহকারী",
  "Report date": "রিপোর্টের তারিখ",
  "Report type": "রিপোর্টের ধরন",
  "Report type not identified": "রিপোর্টের ধরন চেনা যায়নি",
  "Reported hours: {value}": "তালিকাভুক্ত সময়: {value}",
  "Reports and History": "রিপোর্ট ও ইতিহাস",
  "Request Care Team Review": "চিকিৎসা দলের পর্যালোচনা চান",
  "Request a Care Review": "স্বাস্থ্যতথ্যের পর্যালোচনা চান",
  "Request a Care Team Review": "চিকিৎসা দলের পর্যালোচনা চান",
  "Request a clinician review": "চিকিৎসকের পর্যালোচনা চান",
  "Request ambulance": "অ্যাম্বুলেন্সের অনুরোধ করুন",
  "Request cancellation": "বাতিলের অনুরোধ করুন",
  "Request help through a verified Med.ai partner.":
      "যাচাই করা Med.ai সেবাদাতার মাধ্যমে সহায়তা চান।",
  "Request not submitted": "অনুরোধ জমা হয়নি",
  "Request or track an ambulance": "অ্যাম্বুলেন্সের অনুরোধ বা অবস্থান দেখুন",
  "Request: ": "অনুরোধ: ",
  "Requested by": "নির্দেশদাতা চিকিৎসক",
  "Requested by ": "নির্দেশদাতা চিকিৎসক ",
  "Resolve conflict": "সিঙ্কের অমিল সমাধান করুন",
  "Result value": "ফলাফলের মান",
  "Resume following ambulance": "আবার অ্যাম্বুলেন্স অনুসরণ করুন",
  "Retrieve relevant synced readings and report text.":
      "প্রাসঙ্গিক সিঙ্ক করা পরিমাপ ও রিপোর্টের লেখা ব্যবহার করুন।",
  "Retry": "আবার চেষ্টা করুন",
  "Retry OCR": "আবার লেখা পড়ুন",
  "Retry extraction": "আবার তথ্য পড়ুন",
  "Retry same request": "একই অনুরোধ আবার পাঠান",
  "Review Arogga Pack Quantities": "Arogga প্যাকেটের পরিমাণ যাচাই করুন",
  "Review Selections": "নির্বাচন যাচাই করুন",
  "Review a medicine against your prescription before setting its reminders.":
      "রিমাইন্ডার দেওয়ার আগে প্রেসক্রিপশনের সঙ্গে ওষুধ যাচাই করুন।",
  "Review a medicine before creating its reminder.":
      "রিমাইন্ডার তৈরির আগে ওষুধ যাচাই করুন।",
  "Review and save this medicine before choosing alternatives.":
      "বিকল্প বাছার আগে ওষুধ যাচাই করে সংরক্ষণ করুন।",
  "Review details": "তথ্য যাচাই করুন",
  "Review medicine for purchase": "কেনার জন্য ওষুধ যাচাই করুন",
  "Review medicine to enable purchase": "কেনাকাটা চালু করতে ওষুধ যাচাই করুন",
  "Review medicines and get a verified price to calculate quantities.":
      "পরিমাণের হিসাব করতে ওষুধ ও দাম যাচাই করুন।",
  "Review prescribed medicine details": "প্রেসক্রিপশনের ওষুধের তথ্য যাচাই করুন",
  "Review price matches": "দামের মিল যাচাই করুন",
  "Review quantities and medicine details": "ওষুধের তথ্য ও পরিমাণ যাচাই করুন",
  "Review report details": "রিপোর্টের তথ্য যাচাই করুন",
  "Review the instructions first. As-needed medicines are not put on a fixed schedule.":
      "আগে নির্দেশনা যাচাই করুন। প্রয়োজনে খাওয়ার ওষুধ নির্দিষ্ট সময়সূচিতে রাখা হয় না।",
  "Review the prescription to calculate the quantity.":
      "পরিমাণের হিসাব করতে প্রেসক্রিপশন যাচাই করুন।",
  "Review your readings, trends and uploaded lab reports.":
      "আপনার পরিমাপ, পরিবর্তনের ধারা ও আপলোড করা রিপোর্ট দেখুন।",
  "Review your submitted cases and responses.":
      "আপনার জমা দেওয়া অনুরোধ ও উত্তর দেখুন।",
  "Review {value} unfinished items": "{value}টি অসম্পূর্ণ পণ্য যাচাই করুন",
  "Review, edit and save medicine →": "ওষুধ যাচাই, সম্পাদনা ও সংরক্ষণ করুন →",
  "Reviewed Health References": "পর্যালোচিত স্বাস্থ্যতথ্য",
  "Reviewed by you": "আপনার যাচাই করা",
  "Route": "প্রয়োগের পথ",
  "Routed OCR pilot": "ছবি থেকে তথ্য পড়ার পরীক্ষামূলক সেবা",
  "Run OCR": "ছবির লেখা পড়ুন",
  "Save": "সংরক্ষণ করুন",
  "Save Details": "তথ্য সংরক্ষণ করুন",
  "Save Document Securely": "নিরাপদে নথি সংরক্ষণ করুন",
  "Save Medication": "ওষুধ সংরক্ষণ করুন",
  "Save Profile": "প্রোফাইল সংরক্ষণ করুন",
  "Save and Schedule on This Device": "এই ডিভাইসে সংরক্ষণ ও সময়সূচি দিন",
  "Save meal times": "খাবারের সময় সংরক্ষণ করুন",
  "Save report": "রিপোর্ট সংরক্ষণ করুন",
  "Save value": "মান সংরক্ষণ করুন",
  "Save {value} as a preference?": "{value} পছন্দ হিসেবে সংরক্ষণ করবেন?",
  "Saved encrypted on this device and queued for sync.":
      "ডিভাইসে এনক্রিপ্ট করে সংরক্ষিত এবং সিঙ্কের অপেক্ষায়।",
  "Saved on this device. Connect to the backend and use Sync now above. Review opens after upload completes.":
      "এই ডিভাইসে সংরক্ষিত। সার্ভারে সংযোগ দিয়ে উপরে এখন সিঙ্ক করুন চাপুন। আপলোড শেষে পর্যালোচনা খুলবে।",
  "Saving your prescription securely…": "নিরাপদে প্রেসক্রিপশন সংরক্ষণ হচ্ছে…",
  "Saving…": "সংরক্ষণ হচ্ছে…",
  "Say you need an ambulance, or use the request button.":
      "অ্যাম্বুলেন্স প্রয়োজন বলুন অথবা অনুরোধ বোতাম চাপুন।",
  "Scan Prescription": "প্রেসক্রিপশন স্ক্যান করুন",
  "Scan prescription or upload a report":
      "প্রেসক্রিপশন স্ক্যান বা রিপোর্ট আপলোড করুন",
  "Schedule": "সময়সূচি দিন",
  "Scheduling…": "সময়সূচি তৈরি হচ্ছে…",
  "Search References": "তথ্যসূত্র খুঁজুন",
  "Search another area": "অন্য এলাকায় খুঁজুন",
  "Search by doctor, specialty or clinic":
      "ডাক্তার, বিশেষত্ব বা ক্লিনিক দিয়ে খুঁজুন",
  "Search doctors by specialty, clinic or division.":
      "বিশেষত্ব, ক্লিনিক বা বিভাগ দিয়ে ডাক্তার খুঁজুন।",
  "Search opens in Google Maps. Contact a pharmacy directly to confirm medicine stock and current prices.":
      "খোঁজ Google Maps-এ খুলবে। মজুত ও বর্তমান দাম নিশ্চিত করতে ফার্মেসিতে যোগাযোগ করুন।",
  "Search radius": "খোঁজার পরিসর",
  "Search reports": "রিপোর্ট খুঁজুন",
  "Search words": "খোঁজার শব্দ",
  "See all →": "সব দেখুন →",
  "See how many individual units fit your budget, then check separately what Arogga can supply in packs.":
      "বাজেটে কত একক ওষুধ হয় দেখুন, তারপর Arogga-তে প্যাকেটে কত পাওয়া যায় যাচাই করুন।",
  "Select": "বেছে নিন",
  "Select each exact brand, strength and form. Prices are for the listed pack; prescribe and log quantities in individual units.":
      "সঠিক ব্র্যান্ড, শক্তি ও ধরন বেছে নিন। দাম তালিকাভুক্ত প্যাকেটের; প্রেসক্রিপশন ও গ্রহণের পরিমাণ আলাদা এককে লিখুন।",
  "Send message": "বার্তা পাঠান",
  "Send request": "অনুরোধ পাঠান",
  "Set My Budget": "আমার বাজেট দিন",
  "Set an explicit duration in days, weeks or months before enabling automatic alarms.":
      "স্বয়ংক্রিয় অ্যালার্মের আগে দিন, সপ্তাহ বা মাসে নির্দিষ্ট মেয়াদ দিন।",
  "Set on hand": "মজুত লিখুন",
  "Set reminder times →": "রিমাইন্ডারের সময় দিন →",
  "Set the usual time you eat each meal. Before/after offsets are optional; enter them only if confirmed by your clinician or pharmacist. These settings update eligible medicines together. Prescribed times and intervals take priority.":
      "প্রতিদিনের খাবারের সাধারণ সময় দিন। আগে/পরের ব্যবধান ঐচ্ছিক; চিকিৎসক বা ফার্মাসিস্ট নিশ্চিত করলে লিখুন। উপযুক্ত সব ওষুধে একসঙ্গে প্রয়োগ হবে। প্রেসক্রিপশনের নির্দিষ্ট সময় ও বিরতি অগ্রাধিকার পাবে।",
  "Set up meal times": "খাবারের সময় দিন",
  "Set up reminders after saving": "সংরক্ষণের পরে রিমাইন্ডার দিন",
  "Set up your meal times": "আপনার খাবারের সময় দিন",
  "Set your pickup coordinates and allow location sharing first.":
      "আগে পিকআপ স্থানাঙ্ক ও অবস্থান ভাগ করার অনুমতি দিন।",
  "Share selected records with your care team.":
      "চিকিৎসা দলের সঙ্গে নির্বাচিত রেকর্ড ভাগ করুন।",
  "Share your concern and saved records.":
      "আপনার সমস্যা ও সংরক্ষিত রেকর্ড পাঠান।",
  "Share your pickup location, phone and optional details with the selected partner. A request does not confirm dispatch.":
      "নির্বাচিত সেবাদাতাকে পিকআপ স্থান, ফোন ও ঐচ্ছিক তথ্য পাঠান। অনুরোধ মানেই অ্যাম্বুলেন্স পাঠানো নিশ্চিত নয়।",
  "Share your readings in a review request.":
      "পর্যালোচনার অনুরোধে আপনার পরিমাপ পাঠান।",
  "Share your saved records with the configured care team.":
      "নির্ধারিত চিকিৎসা দলের সঙ্গে সংরক্ষিত রেকর্ড ভাগ করুন।",
  "Show password": "পাসওয়ার্ড দেখান",
  "Show under Antibiotics": "অ্যান্টিবায়োটিক বিভাগে দেখান",
  "Showing device records. Some items may not be synced.":
      "ডিভাইসের রেকর্ড দেখানো হচ্ছে। কিছু তথ্য সিঙ্ক না-ও হতে পারে।",
  "Sign in again": "আবার লগইন করুন",
  "Sign in again to fetch medicine prices and prepare your cart. Your saved medicine list is kept on this device.":
      "দাম আনতে ও কার্ট তৈরি করতে আবার লগইন করুন। ওষুধের তালিকা ডিভাইসে আছে।",
  "Sign in again to view your records.": "রেকর্ড দেখতে আবার লগইন করুন।",
  "Sign in for partner dispatch": "সেবাদাতার অ্যাম্বুলেন্সের জন্য লগইন করুন",
  "Sign out": "সাইন আউট",
  "Sign out?": "সাইন আউট করবেন?",
  "Some changes have not synced. They stay encrypted on this device and can sync when you sign in again.":
      "কিছু পরিবর্তন সিঙ্ক হয়নি। এগুলো ডিভাইসে এনক্রিপ্ট করা আছে; আবার লগইন করলে সিঙ্ক হবে।",
  "Source Document": "মূল নথি",
  "Source content SHA-256": "উৎসের SHA-256",
  "Source document (optional)": "মূল নথি (ঐচ্ছিক)",
  "Source language": "উৎসের ভাষা",
  "Source text: {value}": "উৎসের লেখা: {value}",
  "Sources are approved by your configured care team. Retrieval does not verify clinical correctness, diagnose symptoms, or recommend treatment. Ask your care team when unsure.":
      "উৎস আপনার নির্ধারিত চিকিৎসা দল অনুমোদন করেছেন। তথ্য খোঁজা চিকিৎসাগত নির্ভুলতা, রোগনির্ণয় বা চিকিৎসার পরামর্শ নিশ্চিত করে না। সন্দেহ হলে দলকে জিজ্ঞাসা করুন।",
  "Sources used": "ব্যবহৃত তথ্যসূত্র",
  "Speak an ambulance request": "কথা বলে অ্যাম্বুলেন্স চান",
  "Special instructions": "বিশেষ নির্দেশনা",
  "Specialties": "বিশেষত্ব",
  "Statistics": "পরিসংখ্যান",
  "Statistics summary mode": "পরিসংখ্যানের সারসংক্ষেপ মোড",
  "Stay here": "এখানেই থাকুন",
  "Still needed for course: {value}": "কোর্সে আরও প্রয়োজন: {value}",
  "Stop Assistant": "সহকারী বন্ধ করুন",
  "Street map is not configured. GPS markers still show the relative positions.":
      "রাস্তার মানচিত্র সেটআপ করা নেই। জিপিএস চিহ্ন আপেক্ষিক অবস্থান দেখাচ্ছে।",
  "Strength": "শক্তি",
  "Submit Review Request": "পর্যালোচনার অনুরোধ পাঠান",
  "Submitted requests and documented responses.":
      "জমা দেওয়া অনুরোধ ও সংরক্ষিত উত্তর।",
  "Submitted {value}": "জমা হয়েছে {value}",
  "Submitting request…": "অনুরোধ পাঠানো হচ্ছে…",
  "Submitting…": "পাঠানো হচ্ছে…",
  "Summarize my statistics": "আমার পরিসংখ্যানের সারসংক্ষেপ দিন",
  "Supply is low. Enable notifications for refill reminders.":
      "মজুত কম। আবার কেনার রিমাইন্ডারের জন্য নোটিফিকেশন চালু করুন।",
  "Supply is low. Notification could not be displayed.":
      "মজুত কম। নোটিফিকেশন দেখানো যায়নি।",
  "Symptoms mentioned": "উল্লেখিত লক্ষণ",
  "Sync conflict needs your review": "সিঙ্কের অমিল যাচাই করুন",
  "Sync now": "এখন সিঙ্ক করুন",
  "Syncing securely…": "নিরাপদে সিঙ্ক হচ্ছে…",
  "Take Photo": "ছবি তুলুন",
  "Take a clear photo. Prescription scanning starts automatically.":
      "পরিষ্কার ছবি তুলুন। প্রেসক্রিপশন স্ক্যান স্বয়ংক্রিয়ভাবে শুরু হবে।",
  "Taken": "খাওয়া হয়েছে",
  "Tap the map to adjust the pickup pin.":
      "পিকআপ পিন ঠিক করতে মানচিত্রে চাপুন।",
  "Test a request with a test partner.":
      "পরীক্ষামূলক সেবাদাতার সঙ্গে অনুরোধ পরীক্ষা করুন।",
  "Test alarm sound": "অ্যালার্মের শব্দ পরীক্ষা করুন",
  "The app stores your image encrypted. When connected, it uploads to your configured Med.ai server. Report chat shares relevant text with Groq only after you allow it; the original image stays on your server.":
      "অ্যাপ ছবি এনক্রিপ্ট করে রাখে এবং সংযোগ পেলে আপনার Med.ai সার্ভারে পাঠায়। মূল ছবি ও ব্যক্তিগত রিপোর্ট আপনার সার্ভারেই থাকে।",
  "The assistant works in your on-device Arogga session. You review the cart, handle login/prescription verification and complete payment manually.":
      "সহকারী আপনার ডিভাইসের Arogga সেশনে কাজ করে। কার্ট, লগইন, প্রেসক্রিপশন যাচাই ও অর্থ প্রদান আপনি নিজে করবেন।",
  "The listed strength or dosage form differs from your medicine entry. Check the prescription and choose an exact match before using this price.":
      "তালিকার শক্তি বা ধরন আপনার ওষুধের সঙ্গে মেলে না। দাম ব্যবহার করার আগে প্রেসক্রিপশন যাচাই করে সঠিক পণ্য বেছে নিন।",
  "The prescription stays unchanged. Confirm these times follow it.":
      "প্রেসক্রিপশন অপরিবর্তিত থাকবে। সময়গুলো তা অনুসরণ করে কি না নিশ্চিত করুন।",
  "The prescription will remain unchanged. Ask a pharmacist to verify the exact product before buying or switching brands.":
      "প্রেসক্রিপশন অপরিবর্তিত থাকবে। কেনা বা ব্র্যান্ড বদলানোর আগে সঠিক পণ্য ফার্মাসিস্টকে দিয়ে যাচাই করুন।",
  "The reserve is not a live delivery quote. Change it when the supplier shows the actual fee.":
      "সংরক্ষিত খরচ সরাসরি ডেলিভারির দাম নয়। সরবরাহকারী আসল খরচ দেখালে পরিবর্তন করুন।",
  "The same supplier product is matched to more than one medicine entry. Review duplicate entries before using the cart assistant.":
      "একই পণ্য একাধিক ওষুধে মিলেছে। কার্ট সহকারী ব্যবহারের আগে একই ওষুধ একাধিকবার আছে কি না দেখুন।",
  "These records do not provide automated diagnosis or emergency monitoring.":
      "এই রেকর্ড স্বয়ংক্রিয় রোগনির্ণয় বা জরুরি পর্যবেক্ষণ দেয় না।",
  "This brand, strength or dosage form is not yet supported. Check the saved spelling and strength. We will not guess an alternative.":
      "এই ব্র্যান্ড, শক্তি বা ধরন এখনো সমর্থিত নয়। সংরক্ষিত বানান ও শক্তি যাচাই করুন। অনুমান করে বিকল্প দেওয়া হবে না।",
  "This deletes your saved conversation from Med.ai. Your reports are kept.":
      "এতে Med.ai-এর সংরক্ষিত কথোপকথন মুছে যাবে। রিপোর্ট থাকবে।",
  "This dose could not be saved.": "এই ডোজ সংরক্ষণ করা যায়নি।",
  "This is guidance on where to seek care, not a diagnosis.":
      "এটি চিকিৎসাসেবা খোঁজার নির্দেশনা, রোগনির্ণয় নয়।",
  "This medicine already has a daily reminder at that time.":
      "এই ওষুধের জন্য ওই সময়ে রিমাইন্ডার আগে থেকেই আছে।",
  "This offline reference has expired. Connect and refresh the library.":
      "অফলাইন তথ্যসূত্রের মেয়াদ শেষ। সংযোগ দিয়ে তথ্যভান্ডার হালনাগাদ করুন।",
  "This queue is not an emergency service and may not be monitored continuously. Do not wait here for urgent help.":
      "এই অপেক্ষমাণ তালিকা জরুরি সেবা নয় এবং সবসময় দেখা না-ও হতে পারে। জরুরি সহায়তার জন্য এখানে অপেক্ষা করবেন না।",
  "This reference could not be opened: {value}":
      "তথ্যসূত্র খোলা যায়নি: {value}",
  "This release supports 50 daily reminders per account.":
      "প্রতি অ্যাকাউন্টে ৫০টি দৈনিক রিমাইন্ডার সমর্থিত।",
  "This removes it from your current list and cancels its reminders. Source documents and historical dose logs are kept.":
      "এটি বর্তমান তালিকা থেকে সরিয়ে রিমাইন্ডার বাতিল করবে। মূল নথি ও পুরোনো ডোজের ইতিহাস থাকবে।",
  "This removes the local queued image and its links from entered medicines. Your medicine entries are kept.":
      "অপেক্ষমাণ ছবি ও ওষুধের সঙ্গে ছবির লিংক সরাবে। ওষুধের তথ্য থাকবে।",
  "This replaces unsynced profile, medicine and measurement edits on this device with the server version. Copy any changes you need before continuing. Uploaded documents are kept.":
      "ডিভাইসের সিঙ্ক না হওয়া প্রোফাইল, ওষুধ ও পরিমাপের বদলে সার্ভারের তথ্য আসবে। প্রয়োজনীয় পরিবর্তন আগে কপি করুন। আপলোড করা নথি থাকবে।",
  "This stops future care-team access to this request. Images shared in another active request remain accessible. Copies already viewed or downloaded cannot be recalled.":
      "এই অনুরোধে চিকিৎসা দলের ভবিষ্যৎ প্রবেশ বন্ধ হবে। অন্য সক্রিয় অনুরোধের ছবি দেখা যাবে। আগে দেখা বা ডাউনলোড করা কপি ফেরত নেওয়া যায় না।",
  "Timing needs confirmation": "সময় নিশ্চিত করা প্রয়োজন",
  "Today’s doses": "আজকের ডোজ",
  "Too many reminder times": "রিমাইন্ডারের সংখ্যা বেশি",
  "Total budget (BDT, including delivery)": "মোট বাজেট (ডেলিভারিসহ টাকা)",
  "Track the supply after saving from your medicine list.":
      "সংরক্ষণের পরে ওষুধের তালিকা থেকে মজুতের হিসাব রাখুন।",
  "Trend shows only your entered measurements, spaced by entry order.":
      "আপনার লেখা পরিমাপ শুধু সংরক্ষণের ক্রমে দেখানো হয়েছে।",
  "Try again": "আবার চেষ্টা করুন",
  "Two dated reports in the same unit are needed for a trend.":
      "প্রবণতা দেখতে একই এককের তারিখসহ দুটি রিপোর্ট প্রয়োজন।",
  "Unit price (BDT, optional)": "প্রতি এককের দাম (টাকা, ঐচ্ছিক)",
  "Units per dose as written": "প্রতি ডোজে লেখা পরিমাণ",
  "Unreadable name": "নাম পড়া যায়নি",
  "Untitled report": "নামহীন রিপোর্ট",
  "Up to 20 words in the source language": "উৎসের ভাষায় সর্বোচ্চ ২০টি শব্দ",
  "Update All Online Prices": "সব অনলাইন দাম হালনাগাদ করুন",
  "Upload Document": "নথি আপলোড করুন",
  "Upload File": "ফাইল আপলোড করুন",
  "Upload a report to get started.": "শুরু করতে রিপোর্ট আপলোড করুন।",
  "Upload and review report": "রিপোর্ট আপলোড ও যাচাই করুন",
  "Upload report": "রিপোর্ট আপলোড করুন",
  "Uploaded ": "আপলোড হয়েছে ",
  "Uploaded lab reports will appear here.":
      "আপলোড করা ল্যাব রিপোর্ট এখানে দেখাবে।",
  "Uploaded securely": "নিরাপদে আপলোড হয়েছে",
  "Uploading and reading…": "আপলোড ও পড়া হচ্ছে…",
  "Uploading securely and checking the report. Review opens when the upload finishes.":
      "নিরাপদে আপলোড ও রিপোর্ট যাচাই হচ্ছে। আপলোড শেষে পর্যালোচনা খুলবে।",
  "Use Full Estimate": "পূর্ণ হিসাব ব্যবহার করুন",
  "Use Med.ai Assistant?": "Med.ai সহকারী ব্যবহার করবেন?",
  "Use This Price": "এই দাম ব্যবহার করুন",
  "Use This Product Listing": "এই পণ্য ব্যবহার করুন",
  "Use a manually checked price instead": "নিজের যাচাই করা দাম ব্যবহার করুন",
  "Use location": "অবস্থান ব্যবহার করুন",
  "Use my GPS location": "আমার জিপিএস অবস্থান নিন",
  "Use my Med.ai profile number and request an Arogga SMS code":
      "Med.ai প্রোফাইলের নম্বর দিয়ে Arogga এসএমএস কোড চান",
  "Use my health records": "আমার স্বাস্থ্যতথ্য ব্যবহার করুন",
  "Use only if the medicine label or prescription identifies it as an antibiotic.":
      "ওষুধের লেবেল বা প্রেসক্রিপশনে অ্যান্টিবায়োটিক বলা থাকলেই ব্যবহার করুন।",
  "Use recent location?": "সাম্প্রতিক অবস্থান ব্যবহার করবেন?",
  "Use report-aware AI?": "রিপোর্টভিত্তিক সহকারী ব্যবহার করবেন?",
  "Use the manual request button or call 999.":
      "নিজে অনুরোধের বোতাম চাপুন; জরুরি সহায়তার প্রয়োজন হলে ৯৯৯-এ ফোন করুন।",
  "Use your camera": "ক্যামেরা ব্যবহার করুন",
  "Use your location to show mapped pharmacies. Location is sent only for this search, not saved to your patient record. Listings do not confirm medicine stock.":
      "মানচিত্রের ফার্মেসি দেখাতে অবস্থান ব্যবহার হয়। শুধু এই খোঁজের জন্য পাঠানো হয়, রোগীর রেকর্ডে রাখা হয় না। তালিকা ওষুধের মজুত নিশ্চিত করে না।",
  "Use your phone dialer": "ফোনের ডায়ালার ব্যবহার করুন",
  "Use {value} units ({value} days × {value} per day)":
      "{value} একক ব্যবহার করুন ({value} দিন × দিনে {value})",
  "Using another device": "অন্য ডিভাইস ব্যবহার",
  "Value ({value})": "মান ({value})",
  "Values read from report text": "রিপোর্ট থেকে পড়া মান",
  "Verify these OCR values against the original report.":
      "ছবি থেকে পড়া মান মূল রিপোর্টের সঙ্গে মিলিয়ে নিন।",
  "View All Medicines": "সব ওষুধ দেখুন",
  "View Original Prescription": "মূল প্রেসক্রিপশন দেখুন",
  "View Total": "মোট দেখুন",
  "View all medical documents": "সব চিকিৎসার নথি দেখুন",
  "View clinic listing": "ক্লিনিকের তথ্য দেখুন",
  "View health dashboard": "স্বাস্থ্যের ড্যাশবোর্ড দেখুন",
  "View source listing": "উৎসের তালিকা দেখুন",
  "View submitted review requests and notes.":
      "জমা দেওয়া পর্যালোচনার অনুরোধ ও নোট দেখুন।",
  "View supplier listing": "সরবরাহকারীর তালিকা দেখুন",
  "View uploaded image": "আপলোড করা ছবি দেখুন",
  "Voice confirmation unavailable. Use Send request.":
      "কথা বলে নিশ্চিত করা যাচ্ছে না। অনুরোধ পাঠান চাপুন।",
  "Voice unavailable": "ভয়েস সেবা নেই",
  "Waiting to sync": "সিঙ্কের অপেক্ষায়",
  "Welcome Back": "আবার স্বাগতম",
  "What App Guide sends to Gemini": "অ্যাপ নির্দেশিকা Gemini-তে কী পাঠায়",
  "What would you like reviewed?": "কী পর্যালোচনা করাতে চান?",
  "Withdraw": "প্রত্যাহার করুন",
  "Withdraw sharing": "তথ্য ভাগের অনুমতি প্রত্যাহার করুন",
  "Withdraw sharing?": "তথ্য ভাগের অনুমতি প্রত্যাহার করবেন?",
  "Within 1 km": "১ কিলোমিটারের মধ্যে",
  "Within 3 km": "৩ কিলোমিটারের মধ্যে",
  "Within 5 km": "৫ কিলোমিটারের মধ্যে",
  "Working…": "কাজ চলছে…",
  "Your Android speech provider may process audio online. This shortcut only listens when opened.":
      "Android-এর ভয়েস সেবা অনলাইনে অডিও প্রক্রিয়া করতে পারে। এই শর্টকাট শুধু খোলা থাকলে শোনে।",
  "Your Health": "আপনার স্বাস্থ্য",
  "Your Health History": "আপনার স্বাস্থ্যের ইতিহাস",
  "Your Health · Our AI · A Smarter Tomorrow":
      "আপনার স্বাস্থ্য · আমাদের এআই · আরও সুন্দর আগামী",
  "Your Medication Plan": "আপনার ওষুধের পরিকল্পনা",
  "Your Medicines": "আপনার ওষুধ",
  "Your Profile": "আপনার প্রোফাইল",
  "Your current basket does not include every medicine you still need. Review exclusions with a pharmacist; your prescription remains unchanged.":
      "বর্তমান কার্টে সব প্রয়োজনীয় ওষুধ নেই। বাদ পড়া ওষুধ নিয়ে ফার্মাসিস্টের সঙ্গে আলোচনা করুন; প্রেসক্রিপশন অপরিবর্তিত।",
  "Your encrypted local record is retained for your next sign-in.":
      "পরের লগইনের জন্য ডিভাইসের এনক্রিপ্ট করা রেকর্ড রাখা আছে।",
  "Your entered unit price · {value}": "আপনার লেখা এককের দাম · {value}",
  "Your health at a glance": "এক নজরে আপনার স্বাস্থ্য",
  "Your health records will stay in Med.ai.":
      "আপনার স্বাস্থ্যতথ্য Med.ai-তে থাকবে।",
  "Your medication plan and daily schedule.":
      "আপনার ওষুধের পরিকল্পনা ও দৈনিক সময়সূচি।",
  "Your original report is saved, but no readable text was detected. You can choose the report type and enter the doctor and date below.":
      "মূল রিপোর্ট সংরক্ষিত, তবে লেখা পড়া যায়নি। রিপোর্টের ধরন বেছে নিচে চিকিৎসক ও তারিখ লিখতে পারেন।",
  "Your record was copied to the device clipboard. Paste it only into a location you trust.":
      "রেকর্ড ক্লিপবোর্ডে কপি হয়েছে। শুধু বিশ্বস্ত স্থানে পেস্ট করুন।",
  "Your reports": "আপনার রিপোর্ট",
  "Your reviewed prescription and purchase status.":
      "আপনার যাচাই করা প্রেসক্রিপশন ও কেনাকাটার অবস্থা।",
  "Your stored documents and recorded care activity.":
      "সংরক্ষিত নথি ও চিকিৎসার কার্যক্রম।",
  "Your total budget is below the delivery reserve. Available for medicines: ৳0. Adjust your budget or delivery reserve.":
      "মোট বাজেট ডেলিভারির জন্য রাখা টাকার চেয়ে কম। ওষুধের জন্য আছে: ৳০। বাজেট বা ডেলিভারি খরচ পরিবর্তন করুন।",
  "Your uploaded documents will appear here.": "আপলোড করা নথি এখানে দেখাবে।",
  "{value} Open Med.ai regularly to refresh long courses.":
      "{value} দীর্ঘ কোর্সের সময়সূচি হালনাগাদ করতে নিয়মিত Med.ai খুলুন।",
  "{value} chartable results": "{value}টি চার্টযোগ্য ফলাফল",
  "{value} course units · {value} to buy · {value}":
      "কোর্সে {value} একক · কিনতে হবে {value} · {value}",
  "{value} draft · verify against the image":
      "{value} খসড়া · ছবির সঙ্গে যাচাই করুন",
  "{value} estimate": "{value} আনুমানিক",
  "{value} km straight-line · ": "সরাসরি দূরত্ব {value} কিমি · ",
  "{value} km · {value}": "{value} কিমি · {value}",
  "{value} mapped pharmacies": "মানচিত্রে {value}টি ফার্মেসি",
  "{value} medicines · {value} reminder times":
      "{value}টি ওষুধ · {value}টি রিমাইন্ডার",
  "{value} of {value} units · {value} per unit":
      "{value} / {value} একক · প্রতি একক {value}",
  "{value} pack(s) · {value} units supplied":
      "{value}টি প্যাকেট · মোট {value} একক",
  "{value} prescribed units": "প্রেসক্রিপশনে {value} একক",
  "{value} prescribed units · {value}": "প্রেসক্রিপশনে {value} একক · {value}",
  "{value} readings · {value} reports": "{value}টি পরিমাপ · {value}টি রিপোর্ট",
  "{value} · Report OCR": "{value} · রিপোর্টের পড়া লেখা",
  "{value} · {value} extracted values": "{value} · পড়া {value}টি মান",
  "{value} · {value} pack(s) · {value}":
      "{value} · {value}টি প্যাকেট · {value}",
  "৳{value} per unit · {value}": "প্রতি একক ৳{value} · {value}",
  "Compare these details with your prescription or medicine list. Confirm only if they are correct.\n\n":
      "প্রেসক্রিপশন বা ওষুধের তালিকার সঙ্গে মিলিয়ে নিন। সঠিক হলেই নিশ্চিত করুন।\n\n",
  "Frequency: {value}\nMeal: {value}\nDuration: {value}\n":
      "বারসংখ্যা: {value}\nখাবারের সময়: {value}\nমেয়াদ: {value}\n",
  "Medicine: {value}\nStrength: {value}\nForm: {value}\n":
      "ওষুধ: {value}\nশক্তি: {value}\nধরন: {value}\n",
  "Publisher: {value}\nEdition: {value}\nLanguage: {value}\nAudience: {value}\nJurisdiction: {value}\nTeam approval: {value}\nReview due: {value}":
      "প্রকাশক: {value}\nসংস্করণ: {value}\nভাষা: {value}\nপাঠক: {value}\nপ্রযোজ্য এলাকা: {value}\nদলের অনুমোদন: {value}\nপর্যালোচনার সময়: {value}",
  "Purchase quantity: {value} {value}\n": "কেনার পরিমাণ: {value} {value}\n",
  "Route: {value}\nInstructions: {value}\n\n":
      "প্রয়োগের পথ: {value}\nনির্দেশনা: {value}\n\n",
  "Unit estimate: ৳{value} / {value}\nSource: Arogga · checked {value}":
      "এককের হিসাব: ৳{value} / {value}\nউৎস: Arogga · যাচাই {value}",
  "Your records. Your medicines.\nConnected to your care team.":
      "আপনার রেকর্ড। আপনার ওষুধ।\nআপনার চিকিৎসা দলের সঙ্গে সংযুক্ত।",
  "{value}\n\nContinue only if automatic clock times will not conflict with these directions.":
      "{value}\n\nস্বয়ংক্রিয় সময় এসব নির্দেশনার সঙ্গে বিরোধ না করলেই চালিয়ে যান।",
  "{value}\n{value}\nThrough {value}\n\n":
      "{value}\n{value}\n{value} পর্যন্ত\n\n",
  "{value}\n{value} · {value} · {value} release":
      "{value}\n{value} · {value} · মুক্তির ধরন: {value}",
  "{value} pack(s) · {value} units supplied\nArogga · {value}":
      "{value}টি প্যাকেট · মোট {value} একক\nArogga · {value}",
  "{value} · {value}\n{value}\nReview due {value}":
      "{value} · {value}\n{value}\nপর্যালোচনার সময় {value}",
  "Offline copy · last checked {value}\n{value} {value}. Withdrawals cannot be rechecked while offline.":
      "অফলাইন কপি · সর্বশেষ যাচাই {value}\n{value} {value}। অফলাইনে প্রত্যাহারের অবস্থা যাচাই করা যায় না।",
  "Home": "হোম",
  "Reports": "রিপোর্ট",
  "History": "ইতিহাস",
  "AI Chat": "এআই চ্যাট",
  "Morning": "সকাল",
  "Afternoon": "দুপুর",
  "Night": "রাত",
  "Antibiotics": "অ্যান্টিবায়োটিক",
  "Health History": "স্বাস্থ্যের ইতিহাস",
  "See health trends": "স্বাস্থ্যের পরিবর্তন দেখুন",
  "Prices & budget": "দাম ও বাজেট",
  "Plan your purchases": "কেনাকাটার পরিকল্পনা করুন",
  "Find care nearby": "কাছের চিকিৎসাসেবা",
  "Find doctors and pharmacies": "ডাক্তার ও ফার্মেসি খুঁজুন",
  "Health references": "স্বাস্থ্যতথ্য",
  "Explore health resources": "স্বাস্থ্যতথ্য দেখুন",
  "Care team updates": "চিকিৎসা দলের আপডেট",
  "Follow your requests": "অনুরোধের অগ্রগতি দেখুন",
  "Language": "ভাষা",
  "App language": "অ্যাপের ভাষা",
  "Choose your app language": "অ্যাপের ভাষা বেছে নিন",
  "Language saved": "ভাষা সংরক্ষিত",
  "Settings": "সেটিংস",
  "Required": "প্রয়োজন",
  "Email": "ইমেইল",
  "Email address": "ইমেইল ঠিকানা",
  "Password": "পাসওয়ার্ড",
  "Enter your name": "আপনার নাম লিখুন",
  "Enter your email": "ইমেইল লিখুন",
  "Use at least 10 characters": "অন্তত ১০টি অক্ষর দিন",
  "Birth date (YYYY-MM-DD)": "জন্মতারিখ (YYYY-MM-DD)",
  "Emergency contact name": "জরুরি যোগাযোগের নাম",
  "Emergency contact phone": "জরুরি যোগাযোগের ফোন",
  "Medical notes": "চিকিৎসার নোট",
  "Your health, ": "আপনার স্বাস্থ্য, ",
  "Internal Medicine": "মেডিসিন",
  "Cardiology": "হৃদরোগ",
  "Dermatology": "চর্মরোগ",
  "Neurology": "স্নায়ুরোগ",
  "Orthopedics": "হাড় ও জয়েন্ট",
  "ENT": "নাক-কান-গলা",
  "Gastroenterology": "পরিপাকতন্ত্র",
  "Ophthalmology": "চক্ষু",
  "Pediatrics": "শিশু বিভাগ",
  "Not tracked": "হিসাব রাখা হয়নি",
  "not tracked": "হিসাব রাখা হয়নি",
  "Stop": "থামান",
  "Individual units actually taken": "বাস্তবে গ্রহণ করা এককের পরিমাণ",
  "Individual units, not packs": "আলাদা একক, প্যাকেট নয়",
  "No ambulance confirmed yet": "এখনো অ্যাম্বুলেন্স নিশ্চিত নয়",
  "Waiting for a driver": "চালকের অপেক্ষায়",
  "Driver accepted": "চালক গ্রহণ করেছেন",
  "On the way": "পথে আছে",
  "At patient location": "রোগীর স্থানে",
  "Completed": "সম্পন্ন",
  "Cancelled": "বাতিল",
  "Status could not be refreshed. Check your connection and sign-in, then retry. The last request status may be stale.":
      "অবস্থা হালনাগাদ করা যায়নি। সংযোগ ও লগইন যাচাই করে আবার চেষ্টা করুন। আগের অবস্থা পুরোনো হতে পারে।",
};

const _moreBangla = <String, String>{
  "About the doctor": "ডাক্তারের পরিচিতি",
  "Account changed during download.": "ডাউনলোডের সময় অ্যাকাউন্ট বদলেছে।",
  "Additional amount for full list": "পুরো তালিকার জন্য বাড়তি প্রয়োজন",
  "Address not mapped": "ঠিকানা মানচিত্রে নেই",
  "Ambulance last reported location": "অ্যাম্বুলেন্সের সর্বশেষ জানা অবস্থান",
  "Arogga did not acknowledge the page load.":
      "Arogga পাতা লোড হওয়া নিশ্চিত করেনি।",
  "Arogga sign-in is still required. Complete it before resuming.":
      "এখনো Arogga লগইন প্রয়োজন। চালিয়ে যাওয়ার আগে লগইন করুন।",
  "At pickup location": "পিকআপ স্থানে",
  "Audible alarms for scheduled medicine reminders":
      "নির্ধারিত ওষুধের রিমাইন্ডারের শব্দযুক্ত অ্যালার্ম",
  "Basket total": "কার্টের মোট খরচ",
  "Blood count (CBC)": "রক্তকণিকা পরীক্ষা (CBC)",
  "Blood glucose": "রক্তের গ্লুকোজ",
  "Blood sugar over time (HbA1c)": "দীর্ঘমেয়াদি রক্তের সুগার (HbA1c)",
  "Budget Result": "বাজেটের ফলাফল",
  "Budget remaining": "বাকি বাজেট",
  "Budget saved on this device. Sign in again to calculate prices and prepare the cart.":
      "ডিভাইসে বাজেট সংরক্ষিত। দাম ও কার্টের জন্য আবার লগইন করুন।",
  "By doctor": "চিকিৎসক অনুযায়ী",
  "Cancellation unconfirmed. Contact the center directly.":
      "বাতিল নিশ্চিত হয়নি। সরাসরি কেন্দ্রে যোগাযোগ করুন।",
  "Chamber & hours": "চেম্বার ও সময়",
  "Check the prescribed units against this listing.":
      "তালিকার সঙ্গে প্রেসক্রিপশনের একক মিলিয়ে নিন।",
  "Checking Arogga…": "Arogga দেখা হচ্ছে…",
  "Checking supplier quantity.": "সরবরাহকারীর পরিমাণ যাচাই হচ্ছে।",
  "Checking the product listing…": "পণ্যের তথ্য যাচাই হচ্ছে…",
  "Cholesterol and fats (lipid profile)": "কোলেস্টেরল ও চর্বি (লিপিড প্রোফাইল)",
  "Choose a document up to 8 MB.": "সর্বোচ্চ ৮ মেগাবাইটের নথি বেছে নিন।",
  "Choose a smaller image (up to 6 MB).": "ছোট ছবি দিন (সর্বোচ্চ ৬ মেগাবাইট)।",
  "Choose an image smaller than 12 MB.": "১২ মেগাবাইটের ছোট ছবি দিন।",
  "Choose the confirmed first dose time": "নিশ্চিত প্রথম ডোজের সময় দিন",
  "Choose the meals in order and use offsets from 1 to 180 minutes.":
      "খাবারের সময় সঠিক ক্রমে দিন; ব্যবধান ১ থেকে ১৮০ মিনিট।",
  "Choose the prescribed first dose time":
      "প্রেসক্রিপশনের প্রথম ডোজের সময় দিন",
  "Code requested on Arogga. Enter or autofill the SMS code below and confirm login.":
      "Arogga-তে কোড চাওয়া হয়েছে। এসএমএস কোড লিখে বা অটোফিল করে লগইন নিশ্চিত করুন।",
  "Complete Arogga sign-in below. The assistant will resume after sign-in.":
      "নিচে Arogga লগইন করুন। তারপর সহকারী আবার চলবে।",
  "Configured delivery reserve": "নির্ধারিত ডেলিভারি খরচ",
  "Confirm with the clinic": "ক্লিনিকের সঙ্গে নিশ্চিত করুন",
  "Connecting securely…": "নিরাপদে সংযোগ হচ্ছে…",
  "Copy expired at": "কপির মেয়াদ শেষ",
  "Could not load document": "নথি আনা যায়নি",
  "Could not load the supplier product.": "সরবরাহকারীর পণ্য আনা যায়নি।",
  "Could not obtain your location. Enable Precise location and Google Location Accuracy, then retry outdoors or use the area search below.":
      "অবস্থান পাওয়া যায়নি। নির্ভুল অবস্থান ও Google Location Accuracy চালু করুন; বাইরে গিয়ে আবার চেষ্টা করুন বা নিচে এলাকা লিখুন।",
  "Could not open the attachment.": "সংযুক্তি খোলা যায়নি।",
  "Could not open the supplier session.": "সরবরাহকারীর সেশন খোলা যায়নি।",
  "Could not open the supplier session. Close this page and try again.":
      "সরবরাহকারীর সেশন খোলা যায়নি। পাতা বন্ধ করে আবার চেষ্টা করুন।",
  "Could not reach Med.ai. Check your internet connection and try again.":
      "Med.ai-তে সংযোগ হয়নি। ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করুন।",
  "Could not save on this device. Check available storage.":
      "ডিভাইসে সংরক্ষণ হয়নি। খালি জায়গা পরীক্ষা করুন।",
  "Could not unlock the local record. Please sign in again.":
      "ডিভাইসের রেকর্ড খোলা যায়নি। আবার লগইন করুন।",
  "Creating your account…": "অ্যাকাউন্ট তৈরি হচ্ছে…",
  "Date not identified": "তারিখ চেনা যায়নি",
  "Date not listed": "তারিখ উল্লেখ নেই",
  "Delivery charged for this basket": "এই কার্টের ডেলিভারি খরচ",
  "Delivery reserve": "ডেলিভারির জন্য রাখা টাকা",
  "Delivery reserve included": "ডেলিভারির খরচ অন্তর্ভুক্ত",
  "Delivery reserve is too large": "ডেলিভারির জন্য রাখা টাকা বেশি",
  "Describe your request": "অনুরোধের বিবরণ লিখুন",
  "Diastolic blood pressure": "নিচের রক্তচাপ",
  "Directory has no imported records.": "তালিকায় কোনো রেকর্ড আমদানি করা নেই।",
  "Directory is larger than the supported page count.":
      "তালিকা সমর্থিত পাতার সংখ্যার চেয়ে বড়।",
  "Dismiss this test alert when finished.":
      "পরীক্ষা শেষ হলে অ্যালার্ট বন্ধ করুন।",
  "Document was not saved.": "নথি সংরক্ষিত হয়নি।",
  "Driver accepted · dispatch confirmed": "চালক গ্রহণ করেছেন · পাঠানো নিশ্চিত",
  "Emergency warning": "জরুরি সতর্কতা",
  "Enable medication notifications in your device settings.":
      "ডিভাইস সেটিংসে ওষুধের নোটিফিকেশন চালু করুন।",
  "Enter a non-negative BDT amount with up to two decimals":
      "শূন্য বা তার বেশি টাকা লিখুন, সর্বোচ্চ দুই দশমিক",
  "Enter a positive measurement up to 10000":
      "শূন্যের বেশি এবং সর্বোচ্চ 10000-এর পরিমাপ লিখুন",
  "Enter a price with up to two decimals": "সর্বোচ্চ দুই দশমিকে দাম লিখুন",
  "Enter a quantity from 1 to 100000": "1 থেকে 100000-এর পরিমাণ দিন",
  "Enter a whole number from 1 to 99": "1 থেকে 99-এর পূর্ণসংখ্যা দিন",
  "Enter the prescribed strength and dosage form.":
      "প্রেসক্রিপশনের শক্তি ও ওষুধের ধরন দিন।",
  "Enter the result as a number.": "ফলাফল সংখ্যা হিসেবে লিখুন।",
  "Estimated total": "আনুমানিক মোট",
  "Exact passages from the downloaded copy.": "ডাউনলোড করা কপির হুবহু অংশ।",
  "Existing prices were kept.": "আগের দাম রাখা হয়েছে।",
  "Explore specialists and clinic hours.": "বিশেষজ্ঞ ও ক্লিনিকের সময় দেখুন।",
  "External navigation needs your review. Automation has stopped.":
      "বাইরের পাতা যাচাই প্রয়োজন। স্বয়ংক্রিয় কাজ থেমেছে।",
  "Finding pharmacies…": "ফার্মেসি খোঁজা হচ্ছে…",
  "Full Prescription Cost": "সম্পূর্ণ প্রেসক্রিপশনের খরচ",
  "Full purchase estimate": "সম্পূর্ণ কেনাকাটার হিসাব",
  "GPS unavailable. Enter coordinates from a known pickup pin or call 999.":
      "জিপিএস পাওয়া যাচ্ছে না। জানা পিকআপ স্থান থেকে স্থানাঙ্ক দিন; জরুরি হলে ৯৯৯-এ ফোন করুন।",
  "Heart rate": "হৃদস্পন্দন",
  "Hours not listed. Call the clinic to confirm.":
      "সময় উল্লেখ নেই। ক্লিনিকে ফোন করে নিশ্চিত করুন।",
  "Invalid account identifier": "অ্যাকাউন্টের পরিচয় সঠিক নয়",
  "Invalid quantity": "পরিমাণ সঠিক নয়",
  "Invalid source URL": "উৎসের লিংক সঠিক নয়",
  "Known medicine cost": "জানা ওষুধের খরচ",
  "Known total + delivery reserve": "জানা মোট ও ডেলিভারি খরচ",
  "Lab report": "ল্যাব রিপোর্ট",
  "Listing source": "তালিকার উৎস",
  "Live directory unavailable. Showing bundled listings.":
      "লাইভ তালিকা নেই। অ্যাপের সংরক্ষিত তালিকা দেখানো হচ্ছে।",
  "Location denied.": "অবস্থানের অনুমতি নেই।",
  "Location permission is unavailable. Enable it in settings, or search an area below.":
      "অবস্থানের অনুমতি নেই। সেটিংসে চালু করুন বা নিচে এলাকা লিখুন।",
  "Log the dose you actually took": "বাস্তবে গ্রহণ করা ডোজ লিখুন",
  "Low supply threshold": "মজুত কম হওয়ার সীমা",
  "Medication reminder": "ওষুধের রিমাইন্ডার",
  "Medicine Prices": "ওষুধের দাম",
  "Medicine alarms": "ওষুধের অ্যালার্ম",
  "Medicine details changed during review. Review the latest details again.":
      "পর্যালোচনার সময় ওষুধের তথ্য বদলেছে। নতুন তথ্য আবার যাচাই করুন।",
  "Medicine notifications are scheduled at their reminder times.":
      "নির্ধারিত রিমাইন্ডারের সময় নোটিফিকেশন দেওয়া হবে।",
  "Medicine supply is low": "ওষুধের মজুত কম",
  "No appointment contact is listed for this chamber.":
      "এই চেম্বারের অ্যাপয়েন্টমেন্টের যোগাযোগ নেই।",
  "No browser available": "ব্রাউজার নেই",
  "No fields found. Try a clear crop of one field.":
      "তথ্য পাওয়া যায়নি। একটি ঘরের পরিষ্কার কাটা ছবি দিন।",
  "No matching doctors. Try a different search or filter.":
      "ডাক্তার মেলেনি। অন্য শব্দ বা বাছাই দিয়ে খুঁজুন।",
  "No matching partner was able to confirm this request.":
      "কোনো উপযুক্ত সেবাদাতা অনুরোধ নিশ্চিত করতে পারেননি।",
  "No matching source in the current offline copy.":
      "বর্তমান অফলাইন কপিতে উৎস মেলেনি।",
  "No nearby vehicle meets the requested category and equipment. Review the selected category, and keep any equipment you need.":
      "কাছে প্রয়োজনীয় ধরন ও সরঞ্জামের অ্যাম্বুলেন্স নেই। ধরন যাচাই করুন; প্রয়োজনীয় সরঞ্জাম বাদ দেবেন না।",
  "No selected prices could be applied.": "নির্বাচিত দাম প্রয়োগ করা যায়নি।",
  "No staffed partner was reachable within the pickup area.":
      "পিকআপ এলাকায় কর্মীসহ কোনো সেবাদাতার সঙ্গে যোগাযোগ হয়নি।",
  "No test operator is online within range. Open the operator dashboard and check the pickup location.":
      "সীমার মধ্যে পরীক্ষামূলক অপারেটর অনলাইনে নেই। ড্যাশবোর্ড খুলে পিকআপ যাচাই করুন।",
  "No text available. Enter medicine details manually from your source.":
      "লেখা নেই। মূল নথি দেখে নিজে ওষুধের তথ্য লিখুন।",
  "No vehicle matches this category and equipment":
      "এই ধরন ও সরঞ্জামের অ্যাম্বুলেন্স নেই",
  "Not available": "পাওয়া যাচ্ছে না",
  "Not extracted": "পড়া যায়নি",
  "Notifications are scheduled on this device.":
      "এই ডিভাইসে নোটিফিকেশনের সময়সূচি দেওয়া হয়েছে।",
  "Notifications are scheduled. Enable Alarms & reminders for exact alarm times.":
      "নোটিফিকেশনের সময়সূচি তৈরি হয়েছে। নির্ভুল সময়ের জন্য অ্যালার্ম ও রিমাইন্ডারের অনুমতি দিন।",
  "Offline copy expired. Connect and refresh.":
      "অফলাইন কপির মেয়াদ শেষ। সংযোগ দিয়ে রিফ্রেশ করুন।",
  "Offline source status was last checked at download.":
      "ডাউনলোডের সময় সর্বশেষ উৎসের অবস্থা দেখা হয়েছে।",
  "One question": "একটি প্রশ্ন",
  "Online library": "অনলাইন তথ্যভান্ডার",
  "Open Med.ai to check your remaining supply and review what you need to buy.":
      "বাকি মজুত ও কেনার প্রয়োজন দেখতে Med.ai খুলুন।",
  "Open Med.ai to review your prescribed schedule.":
      "প্রেসক্রিপশনের সময়সূচি দেখতে Med.ai খুলুন।",
  "Opening your secure workspace…": "নিরাপদ কর্মক্ষেত্র খোলা হচ্ছে…",
  "Other medical report": "অন্যান্য চিকিৎসার রিপোর্ট",
  "Partner confirmation of cancellation pending":
      "বাতিলের বিষয়ে সেবাদাতার নিশ্চিতকরণের অপেক্ষায়",
  "Paused. You can use Arogga manually or resume verification.":
      "বিরত আছে। Arogga নিজে ব্যবহার করুন বা যাচাই চালিয়ে যান।",
  "Price estimate expired. Refresh the quote.":
      "দামের হিসাবের মেয়াদ শেষ। দাম হালনাগাদ করুন।",
  "Purchase estimate": "কেনার আনুমানিক খরচ",
  "Quantities Within Budget": "বাজেটের মধ্যে পরিমাণ",
  "Quantity needs supplier review.": "পরিমাণ সরবরাহকারীর কাছে যাচাই প্রয়োজন।",
  "Reading available until": "পড়ার সুযোগ আছে",
  "Reading your prescription…": "প্রেসক্রিপশন পড়া হচ্ছে…",
  "Receipt unconfirmed. Retry the same request or refresh status. For urgent help, call 999.":
      "প্রাপ্তি নিশ্চিত নয়। একই অনুরোধ আবার পাঠান বা অবস্থা হালনাগাদ করুন। জরুরি হলে ৯৯৯-এ ফোন করুন।",
  "Record changed on another device. Resolve the sync conflict.":
      "অন্য ডিভাইসে রেকর্ড বদলেছে। সিঙ্কের অমিল সমাধান করুন।",
  "Record units purchased": "কেনা এককের পরিমাণ লিখুন",
  "Reference is not available in the current offline copy.":
      "বর্তমান অফলাইন কপিতে তথ্যসূত্র নেই।",
  "Refill reminders": "আবার কেনার রিমাইন্ডার",
  "Refresh your offline copy while connected.":
      "সংযোগ থাকলে অফলাইন কপি হালনাগাদ করুন।",
  "Remaining purchase quantity": "আরও কেনার পরিমাণ",
  "Reminder update took too long. Tap Save and Schedule to continue.":
      "রিমাইন্ডার হালনাগাদে বেশি সময় লাগছে। চালাতে সংরক্ষণ ও সময়সূচি চাপুন।",
  "Request received · waiting for an operator":
      "অনুরোধ পাওয়া গেছে · অপারেটরের অপেক্ষায়",
  "Review Budget Basket": "বাজেটের কার্ট যাচাই করুন",
  "Review the prescribed strength (including mg/mcg or other unit) and dosage form first.":
      "আগে প্রেসক্রিপশনের শক্তি (mg/mcg বা অন্য এককসহ) ও ওষুধের ধরন যাচাই করুন।",
  "Review the supplier cart before checkout.":
      "চেকআউটের আগে সরবরাহকারীর কার্ট যাচাই করুন।",
  "Review the supplier page. Start only after checking your selected items.":
      "সরবরাহকারীর পাতা দেখুন। নির্বাচিত পণ্য যাচাই করেই শুরু করুন।",
  "Routine care guidance": "সাধারণ চিকিৎসা পরামর্শের নির্দেশনা",
  "Search current approved sources.": "বর্তমানে অনুমোদিত উৎসে খুঁজুন।",
  "Search sources reviewed by your care team.":
      "চিকিৎসা দলের পর্যালোচিত উৎসে খুঁজুন।",
  "Selected medicine cost": "নির্বাচিত ওষুধের খরচ",
  "Selected medicines": "নির্বাচিত ওষুধ",
  "Selected total": "নির্বাচিত মোট",
  "Set Your Budget": "আপনার বাজেট দিন",
  "Set units on hand": "মজুত এককের পরিমাণ দিন",
  "Sign in again to fetch prices and prepare your cart.":
      "দাম আনতে ও কার্ট তৈরি করতে আবার লগইন করুন।",
  "Sign-in was not completed. Finish it on Arogga, then tap Fill / Resume Cart.":
      "লগইন সম্পূর্ণ হয়নি। Arogga-তে শেষ করে কার্ট পূরণ / চালিয়ে যান চাপুন।",
  "Special instruction": "বিশেষ নির্দেশনা",
  "Status not confirmed": "অবস্থা নিশ্চিত নয়",
  "Stock limit is 100,000 units.": "মজুতের সীমা 100,000 একক।",
  "Stored on server": "সার্ভারে সংরক্ষিত",
  "Summarize my health statistics and uploaded lab reports.":
      "আমার স্বাস্থ্যের পরিসংখ্যান ও আপলোড করা রিপোর্টের সারসংক্ষেপ দিন।",
  "Supplier page could not load. Retry or paste its product link.":
      "সরবরাহকারীর পাতা লোড হয়নি। আবার চেষ্টা করুন বা পণ্যের লিংক দিন।",
  "Supplier page failed to load. Use its controls manually or retry.":
      "সরবরাহকারীর পাতা আসেনি। নিজে নিয়ন্ত্রণ করুন বা আবার চেষ্টা করুন।",
  "Supplier product link could not be verified.":
      "সরবরাহকারীর পণ্যের লিংক যাচাই করা যায়নি।",
  "Supplier session cleared. Log in again on Arogga if needed.":
      "সরবরাহকারীর সেশন মুছে গেছে। প্রয়োজনে Arogga-তে আবার লগইন করুন।",
  "Sync is taking too long. Retry when connected.":
      "সিঙ্কে বেশি সময় লাগছে। সংযোগ থাকলে আবার চেষ্টা করুন।",
  "Sync the current medicine list before estimating your basket.":
      "কার্টের হিসাবের আগে বর্তমান ওষুধের তালিকা সিঙ্ক করুন।",
  "Sync this image before requesting OCR. You can enter medicines manually while offline.":
      "লেখা পড়ার অনুরোধের আগে ছবি সিঙ্ক করুন। অফলাইনে নিজে ওষুধ লিখতে পারেন।",
  "Sync unavailable. Locally saved changes will retry when connected.":
      "সিঙ্ক করা যাচ্ছে না। সংযোগ ফিরলে ডিভাইসের পরিবর্তন আবার পাঠানো হবে।",
  "Sync your queued documents before adding more.":
      "আরও যোগ করার আগে অপেক্ষমাণ নথি সিঙ্ক করুন।",
  "Sync your record and documents before submitting a review request.":
      "পর্যালোচনার অনুরোধের আগে রেকর্ড ও নথি সিঙ্ক করুন।",
  "Systolic blood pressure": "উপরের রক্তচাপ",
  "Tap the cart icon on Arogga to continue manually.":
      "নিজে চালাতে Arogga-র কার্ট চিহ্ন চাপুন।",
  "Tap the cart icon on the supplier website to review all items.":
      "সব পণ্য যাচাই করতে সরবরাহকারীর কার্ট চিহ্ন চাপুন।",
  "Test medicine alarm": "ওষুধের অ্যালার্ম পরীক্ষা",
  "The action could not be completed. Please try again.":
      "কাজটি সম্পূর্ণ হয়নি। আবার চেষ্টা করুন।",
  "The estimate changed. Refresh and review the basket before continuing.":
      "হিসাব বদলেছে। চালানোর আগে রিফ্রেশ করে কার্ট যাচাই করুন।",
  "The matching vehicles are busy, offline, or already needed for another request.":
      "মিলে যাওয়া অ্যাম্বুলেন্স ব্যস্ত, অফলাইনে বা অন্য অনুরোধে প্রয়োজন।",
  "The preference was not saved. Check your connection and the current prescription.":
      "পছন্দ সংরক্ষিত হয়নি। সংযোগ ও বর্তমান প্রেসক্রিপশন যাচাই করুন।",
  "The request ended without an accepted assignment. Check nearby partners before trying a new request.":
      "গৃহীত অ্যাম্বুলেন্স ছাড়াই অনুরোধ শেষ হয়েছে। আবার অনুরোধের আগে কাছের সেবাদাতা দেখুন।",
  "The server returned an unexpected response.":
      "সার্ভার অপ্রত্যাশিত উত্তর দিয়েছে।",
  "The supplier page could not be verified.":
      "সরবরাহকারীর পাতা যাচাই করা যায়নি।",
  "The supplier session could not be verified. Use the visible Arogga controls or resume.":
      "সরবরাহকারীর সেশন যাচাই করা যায়নি। Arogga-র বোতাম ব্যবহার করুন বা আবার চালান।",
  "The supplier view stopped responding. Quantity was not confirmed.":
      "সরবরাহকারীর পাতা সাড়া দিচ্ছে না। পরিমাণ নিশ্চিত হয়নি।",
  "There is nothing to price.": "দাম দেওয়ার মতো ওষুধ নেই।",
  "This directory does not show live availability or reserve appointments. Contact the clinic to confirm a date and time.":
      "এই তালিকা লাইভ প্রাপ্যতা দেখায় না বা অ্যাপয়েন্টমেন্ট রাখে না। তারিখ ও সময় নিশ্চিত করতে ক্লিনিকে যোগাযোগ করুন।",
  "This record has reached its logging limit.":
      "এই রেকর্ডে নথিভুক্তির সীমা পূর্ণ।",
  "Thyroid blood test (TSH)": "থাইরয়েড পরীক্ষা (TSH)",
  "Trip completed": "যাত্রা শেষ",
  "Turn on location services, or search an area in Google Maps below.":
      "অবস্থান সেবা চালু করুন বা নিচে Google Maps-এ এলাকা খুঁজুন।",
  "Unknown pack price": "প্যাকেটের দাম অজানা",
  "Updating your estimate…": "হিসাব হালনাগাদ হচ্ছে…",
  "Urine test": "প্রস্রাব পরীক্ষা",
  "Use a Supabase project URL and publishable key.":
      "Supabase প্রকল্পের লিংক ও প্রকাশযোগ্য কী ব্যবহার করুন।",
  "Use the care-team website for clinician accounts.":
      "চিকিৎসকের অ্যাকাউন্টের জন্য চিকিৎসা দলের ওয়েবসাইট ব্যবহার করুন।",
  "Use up to 20 distinct search words.":
      "সর্বোচ্চ ২০টি আলাদা শব্দ দিয়ে খুঁজুন।",
  "Vehicle reserved · waiting for driver acceptance":
      "অ্যাম্বুলেন্স সংরক্ষিত · চালকের গ্রহণের অপেক্ষায়",
  "Verifying product and current price…": "পণ্য ও বর্তমান দাম যাচাই হচ্ছে…",
  "View appointment information": "অ্যাপয়েন্টমেন্টের তথ্য দেখুন",
  "Voice input is unavailable. Try your keyboard microphone or type your message.":
      "ভয়েস ইনপুট নেই। কিবোর্ডের মাইক্রোফোন ব্যবহার করুন বা লিখুন।",
  "Wait for sync to finish and check your connection.":
      "সিঙ্ক শেষ হওয়া পর্যন্ত অপেক্ষা করুন এবং সংযোগ পরীক্ষা করুন।",
  "Waiting for Arogga to load this product.": "Arogga-তে পণ্য লোডের অপেক্ষায়।",
  "What to do next": "পরবর্তী করণীয়",
  "Your budget": "আপনার বাজেট",
  "Your session expired. Sign in to continue.":
      "সেশনের মেয়াদ শেষ। আবার লগইন করুন।",
  "These are proposed around-the-clock times. Use them only if the prescriber confirmed that spacing.\n\n":
      "এগুলো দিন-রাত মিলিয়ে প্রস্তাবিত সময়। চিকিৎসক এই বিরতি নিশ্চিত করলেই ব্যবহার করুন।\n\n",
  "Your records and questions are processed on your Med.ai server. Optional AI definitions use only a fixed public glossary. Verify report values against the original.":
      "আপনার রেকর্ড ও প্রশ্ন আপনার Med.ai সার্ভারে প্রক্রিয়াকরণ হয়। ঐচ্ছিক এআই শুধু নির্দিষ্ট সাধারণ শব্দতালিকা ব্যবহার করে। মূল রিপোর্টের সঙ্গে মান যাচাই করুন।",
  "The app encrypts your image and uploads it to your configured Med.ai server when connected. Your personal reports and questions stay on that server.":
      "অ্যাপ ছবি এনক্রিপ্ট করে সংযোগ পেলে আপনার Med.ai সার্ভারে পাঠায়। ব্যক্তিগত রিপোর্ট ও প্রশ্ন ওই সার্ভারেই থাকে।",
  "Use AI Chat to find relevant doctors or ask about your saved records. This app does not diagnose or monitor emergencies.":
      "প্রাসঙ্গিক ডাক্তার খুঁজতে বা সংরক্ষিত রেকর্ড নিয়ে জানতে এআই চ্যাট ব্যবহার করুন। অ্যাপ রোগনির্ণয় বা জরুরি পর্যবেক্ষণ করে না।",
  "connected": "সংযুক্ত",
  "Dose recorded today": "আজ ওষুধ গ্রহণ নথিভুক্ত হয়েছে",
  "Same-day assessment": "আজই চিকিৎসা মূল্যায়ন",
  "tablet": "ট্যাবলেট",
  "capsule": "ক্যাপসুল",
  "Enteric-coated capsule": "এন্টারিক-কোটেড ক্যাপসুল",
  "immediate": "তাৎক্ষণিক",
  "delayed": "বিলম্বিত",
};
const _bangla = <String, String>{
  "Sign in before saving medicine details.":
      "ওষুধের তথ্য সংরক্ষণের আগে সাইন ইন করুন।",
  "Medicine saved on this device.": "এই ডিভাইসে ওষুধের তথ্য সংরক্ষিত হয়েছে।",
  "Medicine saved. Open Medicine Reminders to finish scheduling.":
      "ওষুধ সংরক্ষিত হয়েছে। রিমাইন্ডার সেটআপ শেষ করতে Medicine Reminders খুলুন।",
  "Check the highlighted fields.": "চিহ্নিত ঘরগুলোর তথ্য যাচাই করুন।",

  "Medical report": "মেডিকেল রিপোর্ট",
  "Med.ai automatically identifies the report type. If needed, the image is read by your configured Groq service.":
      "Med.ai স্বয়ংক্রিয়ভাবে রিপোর্টের ধরন শনাক্ত করে। প্রয়োজনে আপনার কনফিগার করা Groq সেবায় ছবিটি পড়া হয়।",
  "Identifying report type…": "রিপোর্টের ধরন শনাক্ত করা হচ্ছে…",
  "Automatically identified": "স্বয়ংক্রিয়ভাবে শনাক্ত হয়েছে",
  "Automatic identification could not finish. Your original report is saved.":
      "স্বয়ংক্রিয় শনাক্তকরণ সম্পন্ন হয়নি। আপনার মূল রিপোর্ট সংরক্ষিত আছে।",
  "Retry identification": "আবার শনাক্ত করুন",
  "Report type could not be identified confidently. You can keep it as a medical report or correct it below.":
      "রিপোর্টের ধরন নিশ্চিতভাবে শনাক্ত করা যায়নি। মেডিকেল রিপোর্ট হিসেবে রাখতে পারেন অথবা নিচে সংশোধন করতে পারেন।",
  "Your original report is saved, but no readable text was detected. Retry identification with a clearer image, or optionally correct the details below.":
      "মূল রিপোর্ট সংরক্ষিত আছে, তবে পড়ার মতো লেখা শনাক্ত হয়নি। পরিষ্কার ছবি দিয়ে আবার চেষ্টা করুন অথবা চাইলে নিচের তথ্য সংশোধন করুন।",
  "Check the suggested test and requesting doctor. You can correct the automatic label if needed.":
      "শনাক্ত করা পরীক্ষা ও অনুরোধকারী ডাক্তারের তথ্য মিলিয়ে নিন। প্রয়োজনে স্বয়ংক্রিয় লেবেল সংশোধন করতে পারেন।",
  "Blood count (Complete blood count (CBC))":
      "রক্তের কোষ গণনা (Complete blood count (CBC))",
  "Blood sugar test (Blood glucose)": "রক্তের শর্করা পরীক্ষা (Blood glucose)",
  "Thyroid function (Thyroid function tests)":
      "থাইরয়েডের কার্যকারিতা (Thyroid function tests)",
  "Thyroid blood test (Thyroid-stimulating hormone (TSH))":
      "থাইরয়েড রক্ত পরীক্ষা (Thyroid-stimulating hormone (TSH))",
  "Cholesterol and fats (Lipid profile)": "কোলেস্টেরল ও চর্বি (Lipid profile)",
  "Kidney function (Renal function tests)":
      "কিডনির কার্যকারিতা (Renal function tests)",
  "Kidney blood test (Serum creatinine)":
      "কিডনির রক্ত পরীক্ষা (Serum creatinine)",
  "Blood salts (Serum electrolytes)": "রক্তের লবণ (Serum electrolytes)",
  "Liver function (Liver function tests)":
      "লিভারের কার্যকারিতা (Liver function tests)",
  "Urine test (Urinalysis)": "প্রস্রাব পরীক্ষা (Urinalysis)",
  "Stool test (Stool examination)": "মল পরীক্ষা (Stool examination)",
  "Dengue test (Dengue antigen / antibody test)":
      "ডেঙ্গু পরীক্ষা (Dengue antigen / antibody test)",
  "Inflammation blood test (C-reactive protein (CRP))":
      "প্রদাহের রক্ত পরীক্ষা (C-reactive protein (CRP))",
  "Inflammation blood test (Erythrocyte sedimentation rate (ESR))":
      "প্রদাহের রক্ত পরীক্ষা (Erythrocyte sedimentation rate (ESR))",
  "Heart electrical test (Electrocardiogram (ECG))":
      "হৃদযন্ত্রের বৈদ্যুতিক পরীক্ষা (Electrocardiogram (ECG))",
  "Heart ultrasound (Echocardiogram)":
      "হৃদযন্ত্রের আল্ট্রাসাউন্ড (Echocardiogram)",
  "X-ray report (X-ray)": "এক্স-রে রিপোর্ট (X-ray)",
  "Ultrasound report (Ultrasonography (USG))":
      "আল্ট্রাসাউন্ড রিপোর্ট (Ultrasonography (USG))",
  "CT scan report (Computed tomography (CT))":
      "সিটি স্ক্যান রিপোর্ট (Computed tomography (CT))",
  "MRI scan report (Magnetic resonance imaging (MRI))":
      "এমআরআই রিপোর্ট (Magnetic resonance imaging (MRI))",
  "Tissue examination (Histopathology / biopsy report)":
      "টিস্যু পরীক্ষা (Histopathology / biopsy report)",
  "Multiple tests (Combined medical tests)":
      "একাধিক পরীক্ষা (Combined medical tests)",
  "Other report (Other medical report)":
      "অন্যান্য মেডিকেল রিপোর্ট (Other medical report)",
  ..._primaryBangla,
  ..._moreBangla,
};
