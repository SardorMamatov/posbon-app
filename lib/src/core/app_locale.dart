import 'package:flutter/material.dart';

enum AppLocale {
  uz('uz', 'O\'zbekcha', '🇺🇿'),
  ru('ru', 'Русский', '🇷🇺'),
  en('en', 'English', '🇬🇧');

  const AppLocale(this.code, this.label, this.flag);

  final String code;
  final String label;
  final String flag;

  static AppLocale fromCode(String? code) {
    for (final locale in AppLocale.values) {
      if (locale.code == code) return locale;
    }
    return AppLocale.uz;
  }
}

class AppStrings {
  const AppStrings._(this._map);

  final Map<String, String> _map;

  String t(String key) => _map[key] ?? key;

  static const Map<AppLocale, Map<String, String>> _data = {
    AppLocale.uz: {
      'app.title': 'Posbon',
      'app.subtitle': 'Telefoningiz uchun xavfsizlik paneli',
      'app.name_short': 'POSBON',
      'app.slogan': 'Telefoningiz qo\'riqchisi',

      'nav.home': 'Asosiy',
      'nav.apps': 'Ilovalar',
      'nav.results': 'Natijalar',
      'nav.settings': 'Sozlamalar',

      'common.continue': 'Davom etish',
      'common.cancel': 'Bekor qilish',
      'common.back': 'Orqaga',
      'common.save': 'Saqlash',
      'common.delete': 'O\'chirish',
      'common.copy': 'Nusxalash',
      'common.close': 'Yopish',
      'common.search': 'Qidirish',
      'common.loading': 'Yuklanmoqda...',
      'common.yes': 'Ha',
      'common.no': 'Yo\'q',
      'common.agree': 'Roziman',
      'common.not_available': 'Mavjud emas',

      'status.safe': 'Xavfsiz',
      'status.suspicious': 'Shubhali',
      'status.dangerous': 'Xavfli',
      'status.all': 'Barchasi',

      'home.scan_cta_title': 'Bir bosishda telefonni tekshiring',
      'home.scan_cta_body_empty':
          'Ilovalar va APK fayllarni tekshirib, xavfli yoki shubhali holatlarni bir joyda ko\'ring.',
      'home.scan_cta_body_done':
          'Yangi o\'rnatilgan ilovalar yoki yuklangan APK bo\'lsa, qayta tekshiruv qilib holatni yangilang.',
      'home.scan_launch': 'Skanerlashni boshlash',
      'home.scan_launch_sub': 'Ilova, APK va tarixni yangilash',
      'home.pill_main_scan': 'Asosiy tekshiruv',
      'home.no_results': 'Hali natija yo\'q',
      'home.results_count': '{n} ta natija topildi',
      'home.quick_access': 'Tez kirish',
      'home.files_title': 'Fayllar',
      'home.files_sub': 'APK va yuklangan fayllarni tekshirish',
      'home.apps_title': 'Ilovalar',
      'home.apps_sub': 'O\'rnatilgan ilovalarni baholash',
      'home.safe_title': 'Posbon Safe',
      'home.safe_sub': 'PIN bilan himoyalangan parollar',
      'home.hint_no_scan':
          'Hali skan qilinmagan. Tekshiruvni boshlash uchun yuqoridagi tugmani bosing.',
      'home.hint_done':
          'Oxirgi tekshiruv natijalari shu sessiyada yangilangan.',
      'home.scanning_now': 'Skanerlanmoqda',
      'home.scanning_bg': 'Tekshiruv fonda davom etmoqda',
      'home.open_scan': 'Ochish',
      'home.live_monitor': 'Jonli kuzatuv yoqilgan',
      'home.live_monitor_off': 'Jonli kuzatuv o\'chirilgan',

      'scan.title': 'Skanerlash...',
      'scan.progress': '{n} / {t} ta element tekshirildi',
      'scan.hint_background':
          'Tekshiruv uzoq chozilib qolsa, fon rejimida davom etadi va tugagach bildirishnoma yuboriladi.',
      'scan.background_btn': 'Fonda davom etsin',
      'scan.background_on': 'Tekshiruv fon rejimida davom etadi.',
      'scan.notification_title': 'POSBON skani tugadi',
      'scan.bg_start_title': 'Skan fonda',
      'scan.bg_start_body':
          'Tekshiruv fon rejimida davom etmoqda, tugagach xabar beriladi.',

      'files.title': 'Fayllar',
      'files.subtitle_ok': 'Download papkasidagi APK lar ko\'rsatiladi.',
      'files.subtitle_no_perm':
          'Download papkasini ko\'rish uchun fayl ruxsatini yoqing.',
      'files.count_found': '{n} ta APK topildi',
      'files.bg_hint':
          'Fon kuzatuvi yangi APK tushsa uni avtomatik tekshiradi.',
      'files.scan_all': 'Hammasini tekshirish',
      'files.pick': 'Fayl tanlash',
      'files.permission': 'Ruxsat',
      'files.empty_title': 'Download papkasida APK topilmadi',
      'files.empty_desc':
          'Fayl tanlash orqali alohida APK ni tekshirishingiz mumkin.',

      'results.title': 'Skan natijasi',
      'results.subtitle': 'Kartaga bosing va sabablarini ko\'ring.',
      'results.empty_title': 'Barchasi xavfsiz',
      'results.empty_desc': 'Hozircha tahdid aniqlanmadi.',
      'results.filter_dangerous_only': 'Faqat xavfli',
      'results.filter_suspicious_only': 'Faqat shubhali',
      'results.filter_safe_only': 'Faqat xavfsiz',
      'results.reasons': 'Sabablar',
      'results.delete_file': 'Faylni o\'chirish',

      'apps.title': 'O\'rnatilgan ilovalar',
      'apps.search_hint': 'Ilovani qidiring',

      'app_detail.source': 'Manba',
      'app_detail.version': 'Versiya',
      'app_detail.installed_date': 'O\'rnatilgan sana',
      'app_detail.updated_date': 'Yangilangan sana',
      'app_detail.risk_level': 'Xavf darajasi',
      'app_detail.permissions': 'Ruxsatlar',
      'app_detail.deep_scan': 'Chuqur tekshirish',
      'app_detail.scanning': 'Tekshirilmoqda...',
      'app_detail.uninstall': 'Ilovani o\'chirish',
      'app_detail.show_more': 'Ko\'proq',
      'app_detail.show_less': 'Kamroq',

      'permissions.title': 'Ruxsatlar talab qilinadi',
      'permissions.body':
          'POSBON qurilmangizni ishonchli nazorat qilishi uchun quyidagi ruxsatlar kerak.',
      'permissions.grant': 'Ruxsat berish',

      'safe.title_vault': 'Parollar',
      'safe.count_label': '{n} ta parol',
      'safe.search_placeholder': 'Nomi yoki login bo\'yicha qidiring',
      'safe.add_password': 'Parol qo\'shish',
      'safe.setup_title': 'Parollarni himoyalangan joyda saqlang',
      'safe.setup_body':
          'Ma\'lumotlar telefonning xavfsiz xotirasida saqlanadi. Kirish uchun PIN o\'rnating.',
      'safe.pin_enter': '4 xonali PIN kiriting',
      'safe.pin_confirm': 'PIN ni qayta kiriting',
      'safe.enable': 'Posbon Safe ni yoqish',
      'safe.locked_title': 'Qulflangan bo\'lim',
      'safe.locked_body':
          'Gmail, bank va boshqa muhim login ma\'lumotlaringiz saqlanadi.',
      'safe.unlock_device': 'Qurilma himoyasi bilan ochish',
      'safe.pin_unlock': 'PIN bilan kirish',
      'safe.pin_unlock_btn': 'PIN bilan ochish',
      'safe.new_credential': 'Yangi parol',
      'safe.new_credential_hint': 'Faqat nom va parol majburiy.',
      'safe.field_name': 'Nomi (ilova yoki xizmat)',
      'safe.field_name_helper': 'Masalan: Gmail, Kapitalbank, Telegram',
      'safe.field_login': 'Login yoki email',
      'safe.field_login_helper': 'Ixtiyoriy, keyinroq nusxalash uchun qulay.',
      'safe.field_password': 'Parol',
      'safe.field_password_helper':
          'Kuchli parolni shu yerda yaratishingiz mumkin.',
      'safe.field_note': 'Izoh',
      'safe.field_note_helper': 'Ixtiyoriy eslatma.',
      'safe.required_badge': 'Majburiy',
      'safe.required_missing': 'Majburiy maydonlar: nomi va parol.',
      'safe.generator_new': 'Yangi parol',
      'safe.generator_length': 'Uzunlik: {n} belgi',
      'safe.strength_weak': 'Zaif',
      'safe.strength_okay': 'O\'rtacha',
      'safe.strength_strong': 'Kuchli',
      'safe.empty_title': 'Posbon Safe bo\'sh',
      'safe.empty_desc':
          'Gmail, bank yoki boshqa muhim loginlarni shu yerda saqlashingiz mumkin.',
      'safe.search_no_results': 'Mos yozuv topilmadi',
      'safe.delete_confirm': 'Yozuvni o\'chirish',

      'settings.title': 'Sozlamalar',
      'settings.language': 'Til tanlash',
      'settings.language_current': 'Hozirgi til',
      'settings.premium': 'Premium',
      'settings.premium_desc': 'Kengaytirilgan imkoniyatlar (tez orada)',
      'settings.support': 'Qo\'llab-quvvatlash',
      'settings.support_desc': 'Biz bilan bog\'laning',
      'settings.privacy': 'Maxfiylik siyosati',
      'settings.privacy_desc': 'Foydalanish shartlari',
      'settings.monitoring': 'Real vaqt kuzatuvi',
      'settings.monitoring_desc': 'Yuklangan fayllarni avtomatik tekshirish',
      'settings.about': 'Ilova haqida',
      'settings.version': 'Versiya',
      'settings.choose_language': 'Tilni tanlang',
      'settings.contact_telegram': 'Telegram',
      'settings.contact_email': 'Email',

      'agreement.title': 'Foydalanish shartlari',
      'agreement.accept': 'Roziman va davom etaman',
      'agreement.checkbox': 'Men shartlarni o\'qib chiqdim va rozi bo\'laman',
      'agreement.body': '''1. Umumiy qoidalar

Ushbu ilova — Posbon — foydalanuvchi qurilmasidagi fayllar va ilovalarni xavfsizlik nuqtai nazaridan tekshirish uchun moʻljallangan. Ilovadan foydalanish bilan siz quyidagi shartlarga rozilik bildirasiz.

2. Xavfsizlik va maxfiylik

Posbon foydalanuvchining shaxsiy maʼlumotlarini uzatmaydi va yigʻmaydi. Barcha jarayonlar qurilma ichida amalga oshiriladi. Faqat sizning ruxsatingiz bilan VirusTotal xizmatiga APK hash yuboriladi.

3. Litsenziya

Foydalanuvchiga ilovani ishlatish uchun bepul, noeksklyuziv litsenziya beriladi. Ilovaning nusxasini koʻpaytirish yoki kodini oʻzgartirish taqiqlanadi.

4. Yakuniy qoidalar

Ilovadan foydalanuvchi shu shartlar bilan tanishib chiqqan va ularni qabul qilgan hisoblanadi.

5. Aloqa

Email: mamatovramazon9258@gmail.com
Telegram: https://t.me/Mamatov_Ramazon''',

      'uninstall.failed': 'Ilovani o\'chirish oynasini ochib bo\'lmadi.',

      'scan.error_downloads': 'Download papkasini o\'qishda xato: {e}',
      'scan.found_dangerous': 'Xavfli APK topildi',
      'scan.found_suspicious': 'Shubhali APK topildi',
      'scan.no_apps': 'Tekshirish uchun ilovalar topilmadi',

      'files.prev_in_progress':
          'Avvalgi tekshiruv tugagach yangi fayl ko\'riladi.',
      'files.delete_missing': 'Fayl allaqachon o\'chirilgan yoki topilmadi.',
      'files.delete_done': 'Fayl o\'chirildi.',
      'files.delete_failed': 'Faylni o\'chirib bo\'lmadi: {e}',
      'files.copied': '{label} nusxalandi.',

      'safe.auth_reason': 'Posbon Safe ma\'lumotlarini ochish uchun tasdiqlang',
      'safe.login': 'Login',
      'safe.password': 'Parol',
      'safe.copy': 'Nusxalash',
      'safe.login_not_set': 'Kiritilmagan',
      'safe.login_none': 'Login qo\'shilmagan',
      'safe.save': 'Saqlash',
      'safe.saving': 'Saqlanmoqda...',
      'safe.protected_badge': 'Himoyalangan',
      'safe.new_login': 'Yangi login',
      'safe.has_generator': 'Generator bor',
      'safe.extra_fields_opt': 'Qo\'shimcha maydonlar ixtiyoriy',
      'safe.main_info': 'Asosiy ma\'lumotlar',
      'safe.main_info_hint':
          'Birinchi ko\'rishda nima kiritishi kerakligi darrov bilinishi uchun asosiy oqim soddalashtirildi.',
      'safe.category': 'Kategoriya',
      'safe.note': 'Izoh',
      'safe.note_hint': 'Ixtiyoriy eslatma.',
      'safe.new_password_btn': 'Yangi parol',
      'safe.extra_fields': 'Qo\'shimcha maydonlar',
      'safe.extra_fields_hint': 'Kategoriya va izoh faqat kerak bo\'lsa.',
      'safe.category_helper':
          'Faqat tartib uchun. Nomi bo\'yicha qidirish ishlaydi, shuning uchun bu ixtiyoriy.',
      'safe.delete_entry': 'Yozuvni o\'chirish',

      'about.title': 'POSBON nima qiladi?',
      'about.apps_title': 'Ilovalarni baholaydi',
      'about.apps_desc':
          'Manba, ruxsatlar va VirusTotal bazasi bo\'yicha holatini ko\'rsatadi.',
      'about.files_title': 'APK fayllarni tekshiradi',
      'about.files_desc':
          'Download papkasidagi yoki qo\'lda tanlangan APK fayllarni skan qiladi.',
      'about.safe_title': 'Posbon Safe',
      'about.safe_desc': 'Parollar va muhim login ma\'lumotlari himoyalanadi.',

      'app_detail.trusted_badge': 'Ishonchli ilovalar ro\'yxatida',
      'app_detail.posbon_note': 'Posbon eslatmasi',
      'app_detail.posbon_note_body':
          'Mashhur ilovalar standart ruxsatlari sababli yolg\'on shubhali bo\'lib qolmasligi uchun alohida ro\'yxat bilan himoyalanadi.',
      'app_detail.summary_title': 'Tekshiruv xulosasi',
      'app_detail.permissions_none':
          'Ruxsat ma\'lumotlari yuklanmoqda yoki mavjud emas',
      'app_detail.vt_dangerous_note':
          'VirusTotal bazasi mosligi topilgani uchun status to\'g\'ridan-to\'g\'ri xavfli qilib ko\'rsatildi.',
      'app_detail.checking': 'Tekshirish',

      'results.location': 'Joylashuv',
      'results.vt_dangerous': 'VirusTotal bazasi bo\'yicha xavfli',
      'results.vt_clean': 'VirusTotal zararli belgi topmadi',
      'results.vt_not_scanned': 'VirusTotal hali tekshirilmagan',

      'files.size_unknown': 'Hajmi noma\'lum',
      'files.moved': 'Ko\'chirib yuborilgan',
      'files.empty_download': 'Download papkasida APK topilmadi',
      'files.subtitle_ok_long':
          'Download papkasidagi APK lar ko\'rsatiladi. Tekshiruvni o\'zingiz boshlaysiz, fon kuzatuvi esa yangi APK tushsa uni qayd etadi.',
      'files.subtitle_no_perm_long':
          'Download papkasini to\'liq ko\'rish uchun fayl ruxsatini yoqing.',

      'about.app_trusted_hint': 'Mashhur ilovalar ro\'yxatida mavjud',

      'scan.external_queued':
          'Tashqi fayl qabul qilindi. Ruxsatlar tugagach avtomatik tekshiriladi.',
      'safe.device_unlock_failed':
          'Qurilma himoyasi bilan ochilmadi. PIN orqali kirib ko\'ring.',

      'onboarding.1.title': 'Xavfsizlik skaneri',
      'onboarding.1.desc':
          'Qurilmangizdagi fayl va ilovalarni bir joyda nazorat qilib, tahdidlarni tez aniqlang.',
      'onboarding.2.title': 'Ilovalarni tekshirish',
      'onboarding.2.desc':
          'O\'rnatilgan dasturlarni ruxsatlar, manba va risk darajasi bo\'yicha kuzating.',
      'onboarding.3.title': 'Fayllarni himoya qilish',
      'onboarding.3.desc':
          'Shubhali fayllarni ajrating va xavfsizlik holatini vizual ko\'rinishda baholang.',

      'perm.notifications.title': 'Bildirishnomalar',
      'perm.notifications.desc': 'Xavf aniqlansa sizni darhol ogohlantiradi.',
      'perm.notifications.granted': 'Bildirishnomalar yoqildi',
      'perm.notifications.denied': 'Bildirishnoma ruxsati berilmadi',

      'perm.files.title': 'Fayllar skani',
      'perm.files.desc': 'Download va boshqa tanlangan fayllarni skan qiladi.',
      'perm.files.note_wide': 'Android {sdk}: keng fayl kirishi so\'raladi',
      'perm.files.note_std': 'Android {sdk}: oddiy storage ruxsati kifoya',
      'perm.files.granted': 'Fayl skani uchun ruxsat berildi',
      'perm.files.denied': 'Fayllarni chuqur tekshirish uchun ruxsat kerak',

      'perm.media.title': 'Media fayllar',
      'perm.media.desc':
          'Rasm, video va audio fayllarni xavfsizlik uchun ko\'radi.',
      'perm.media.note_new':
          'Android 13+ da media ruxsatlari alohida boshqariladi',
      'perm.media.note_old':
          'Eski Androidlarda bu storage ruxsati bilan ishlaydi',
      'perm.media.granted': 'Media fayllar skani yoqildi',
      'perm.media.denied_new':
          'Bu Android versiyada media ruxsat alohida boshqariladi.',
      'perm.media.denied_old':
          'Bu qurilmada media access storage ruxsati orqali ishlaydi.',

      'perm.monitoring.title': 'Monitoring',
      'perm.monitoring.desc':
          'POSBON fon rejimida tezroq ishlashi uchun yordam beradi.',
      'perm.monitoring.granted':
          'Monitoring uchun optimizatsiya cheklovi yechildi',
      'perm.monitoring.denied': 'Fon monitoringi cheklangan holatda ishlaydi',

      'perm.apps.title': 'Dasturlarni tekshirish',
      'perm.apps.desc': 'O\'rnatilgan ilovalar ro\'yxatini tahlil qiladi.',
      'perm.apps.note': 'Android manifest orqali faollashtirilgan',
      'perm.apps.already': 'Ilovalarni tekshirish allaqachon yoqilgan',

      'perm.install.title': 'Xavfsiz o\'rnatish',
      'perm.install.desc': 'APK o\'rnatishdan oldin POSBON orqali tekshiradi.',
      'perm.install.granted': 'APK tekshirish oqimi uchun ruxsat berildi',
      'perm.install.denied':
          'APK o\'rnatishdan oldin tekshiruv uchun bu ruxsat kerak',
    },

    AppLocale.ru: {
      'app.title': 'Posbon',
      'app.subtitle': 'Панель безопасности для вашего телефона',
      'app.name_short': 'POSBON',
      'app.slogan': 'Страж вашего телефона',

      'nav.home': 'Главная',
      'nav.apps': 'Приложения',
      'nav.results': 'Результаты',
      'nav.settings': 'Настройки',

      'common.continue': 'Продолжить',
      'common.cancel': 'Отмена',
      'common.back': 'Назад',
      'common.save': 'Сохранить',
      'common.delete': 'Удалить',
      'common.copy': 'Копировать',
      'common.close': 'Закрыть',
      'common.search': 'Поиск',
      'common.loading': 'Загрузка...',
      'common.yes': 'Да',
      'common.no': 'Нет',
      'common.agree': 'Согласен',
      'common.not_available': 'Недоступно',

      'status.safe': 'Безопасно',
      'status.suspicious': 'Подозрительно',
      'status.dangerous': 'Опасно',
      'status.all': 'Все',

      'home.scan_cta_title': 'Проверьте телефон в один клик',
      'home.scan_cta_body_empty':
          'Проверьте приложения и APK-файлы и увидите все угрозы в одном месте.',
      'home.scan_cta_body_done':
          'Если установлены новые приложения или загружены APK, запустите повторную проверку.',
      'home.scan_launch': 'Начать сканирование',
      'home.scan_launch_sub': 'Обновить приложения, APK и историю',
      'home.pill_main_scan': 'Основная проверка',
      'home.no_results': 'Результатов пока нет',
      'home.results_count': 'Найдено: {n}',
      'home.quick_access': 'Быстрый доступ',
      'home.files_title': 'Файлы',
      'home.files_sub': 'Проверка APK и загруженных файлов',
      'home.apps_title': 'Приложения',
      'home.apps_sub': 'Оценка установленных приложений',
      'home.safe_title': 'Posbon Safe',
      'home.safe_sub': 'Пароли, защищённые PIN-кодом',
      'home.hint_no_scan':
          'Сканирование ещё не запускалось. Нажмите кнопку выше, чтобы начать.',
      'home.hint_done':
          'Результаты последней проверки обновлены в этой сессии.',
      'home.scanning_now': 'Сканирование',
      'home.scanning_bg': 'Проверка продолжается в фоне',
      'home.open_scan': 'Открыть',
      'home.live_monitor': 'Слежение в реальном времени включено',
      'home.live_monitor_off': 'Слежение в реальном времени выключено',

      'scan.title': 'Сканирование...',
      'scan.progress': 'Проверено {n} из {t}',
      'scan.hint_background':
          'Если проверка затянется, она продолжится в фоне и пришлёт уведомление.',
      'scan.background_btn': 'Продолжить в фоне',
      'scan.background_on': 'Проверка продолжается в фоновом режиме.',
      'scan.notification_title': 'POSBON завершил сканирование',
      'scan.bg_start_title': 'Сканирование в фоне',
      'scan.bg_start_body':
          'Проверка продолжается в фоне, вы получите уведомление по завершении.',

      'files.title': 'Файлы',
      'files.subtitle_ok': 'Отображаются APK-файлы из папки Download.',
      'files.subtitle_no_perm':
          'Дайте разрешение на файлы, чтобы увидеть папку Download.',
      'files.count_found': 'Найдено APK: {n}',
      'files.bg_hint': 'Фоновая проверка автоматически сканирует новые APK.',
      'files.scan_all': 'Проверить все',
      'files.pick': 'Выбрать файл',
      'files.permission': 'Разрешить',
      'files.empty_title': 'APK в папке Download не найдены',
      'files.empty_desc': 'Вы можете выбрать отдельный APK для проверки.',

      'results.title': 'Результаты проверки',
      'results.subtitle': 'Нажмите на карточку, чтобы увидеть причины.',
      'results.empty_title': 'Всё в порядке',
      'results.empty_desc': 'Угроз пока не обнаружено.',
      'results.filter_dangerous_only': 'Только опасные',
      'results.filter_suspicious_only': 'Только подозрительные',
      'results.filter_safe_only': 'Только безопасные',
      'results.reasons': 'Причины',
      'results.delete_file': 'Удалить файл',

      'apps.title': 'Установленные приложения',
      'apps.search_hint': 'Поиск приложения',

      'app_detail.source': 'Источник',
      'app_detail.version': 'Версия',
      'app_detail.installed_date': 'Дата установки',
      'app_detail.updated_date': 'Дата обновления',
      'app_detail.risk_level': 'Уровень риска',
      'app_detail.permissions': 'Разрешения',
      'app_detail.deep_scan': 'Глубокая проверка',
      'app_detail.scanning': 'Проверяется...',
      'app_detail.uninstall': 'Удалить приложение',
      'app_detail.show_more': 'Больше',
      'app_detail.show_less': 'Меньше',

      'permissions.title': 'Нужны разрешения',
      'permissions.body':
          'Для надёжного мониторинга POSBON потребуются следующие разрешения.',
      'permissions.grant': 'Разрешить',

      'safe.title_vault': 'Пароли',
      'safe.count_label': 'Паролей: {n}',
      'safe.search_placeholder': 'Поиск по имени или логину',
      'safe.add_password': 'Добавить пароль',
      'safe.setup_title': 'Храните пароли в защищённом месте',
      'safe.setup_body':
          'Данные хранятся в защищённой памяти телефона. Установите PIN для доступа.',
      'safe.pin_enter': 'Введите 4-значный PIN',
      'safe.pin_confirm': 'Повторите PIN',
      'safe.enable': 'Включить Posbon Safe',
      'safe.locked_title': 'Раздел заблокирован',
      'safe.locked_body': 'Здесь хранятся Gmail, банк и другие важные логины.',
      'safe.unlock_device': 'Разблокировать защитой устройства',
      'safe.pin_unlock': 'Войти по PIN',
      'safe.pin_unlock_btn': 'Открыть по PIN',
      'safe.new_credential': 'Новая запись',
      'safe.new_credential_hint': 'Обязательны только имя и пароль.',
      'safe.field_name': 'Название (сервис или приложение)',
      'safe.field_name_helper': 'Например: Gmail, Kapitalbank, Telegram',
      'safe.field_login': 'Логин или email',
      'safe.field_login_helper': 'Необязательно, удобно для копирования.',
      'safe.field_password': 'Пароль',
      'safe.field_password_helper': 'Можно сгенерировать сильный пароль здесь.',
      'safe.field_note': 'Заметка',
      'safe.field_note_helper': 'Необязательная заметка.',
      'safe.required_badge': 'Обязательно',
      'safe.required_missing': 'Обязательные поля: название и пароль.',
      'safe.generator_new': 'Новый пароль',
      'safe.generator_length': 'Длина: {n} символов',
      'safe.strength_weak': 'Слабый',
      'safe.strength_okay': 'Средний',
      'safe.strength_strong': 'Сильный',
      'safe.empty_title': 'Posbon Safe пуст',
      'safe.empty_desc': 'Храните здесь Gmail, банк и другие важные логины.',
      'safe.search_no_results': 'Совпадений не найдено',
      'safe.delete_confirm': 'Удалить запись',

      'settings.title': 'Настройки',
      'settings.language': 'Выбор языка',
      'settings.language_current': 'Текущий язык',
      'settings.premium': 'Premium',
      'settings.premium_desc': 'Расширенные возможности (скоро)',
      'settings.support': 'Поддержка',
      'settings.support_desc': 'Свяжитесь с нами',
      'settings.privacy': 'Политика конфиденциальности',
      'settings.privacy_desc': 'Условия использования',
      'settings.monitoring': 'Мониторинг в реальном времени',
      'settings.monitoring_desc': 'Автопроверка загруженных файлов',
      'settings.about': 'О приложении',
      'settings.version': 'Версия',
      'settings.choose_language': 'Выберите язык',
      'settings.contact_telegram': 'Telegram',
      'settings.contact_email': 'Email',

      'agreement.title': 'Условия использования',
      'agreement.accept': 'Согласен и продолжаю',
      'agreement.checkbox': 'Я прочитал и согласен с условиями',
      'agreement.body': '''1. Общие положения

Приложение Posbon предназначено для проверки безопасности файлов и приложений на устройстве пользователя. Используя приложение, вы соглашаетесь с настоящими условиями.

2. Безопасность и конфиденциальность

Posbon не собирает и не передаёт личные данные пользователя. Все операции выполняются внутри устройства. Только с вашего согласия хеш APK отправляется в службу VirusTotal.

3. Лицензия

Пользователю предоставляется бесплатная неисключительная лицензия. Копирование, изменение кода или распространение запрещены.

4. Заключительные положения

Пользователь считается ознакомленным с условиями и принявшим их.

5. Контакты

Email: mamatovramazon9258@gmail.com
Telegram: https://t.me/Mamatov_Ramazon''',

      'uninstall.failed': 'Не удалось открыть окно удаления.',

      'scan.error_downloads': 'Ошибка чтения папки Download: {e}',
      'scan.found_dangerous': 'Найден опасный APK',
      'scan.found_suspicious': 'Найден подозрительный APK',
      'scan.no_apps': 'Нет приложений для проверки',

      'files.prev_in_progress':
          'Новый файл будет проверен после завершения текущей проверки.',
      'files.delete_missing': 'Файл уже удалён или не найден.',
      'files.delete_done': 'Файл удалён.',
      'files.delete_failed': 'Не удалось удалить файл: {e}',
      'files.copied': '{label} скопировано.',

      'safe.auth_reason': 'Подтвердите, чтобы открыть данные Posbon Safe',
      'safe.login': 'Логин',
      'safe.password': 'Пароль',
      'safe.copy': 'Копировать',
      'safe.login_not_set': 'Не указано',
      'safe.login_none': 'Логин не добавлен',
      'safe.save': 'Сохранить',
      'safe.saving': 'Сохранение...',
      'safe.protected_badge': 'Защищено',
      'safe.new_login': 'Новый логин',
      'safe.has_generator': 'Есть генератор',
      'safe.extra_fields_opt': 'Доп. поля необязательны',
      'safe.main_info': 'Основная информация',
      'safe.main_info_hint':
          'Основной поток упрощён, чтобы сразу было понятно, что нужно ввести при первом добавлении.',
      'safe.category': 'Категория',
      'safe.note': 'Заметка',
      'safe.note_hint': 'Необязательная заметка.',
      'safe.new_password_btn': 'Новый пароль',
      'safe.extra_fields': 'Дополнительные поля',
      'safe.extra_fields_hint':
          'Категория и заметка — только при необходимости.',
      'safe.category_helper':
          'Только для удобства. Поиск работает по названию, поэтому это необязательно.',
      'safe.delete_entry': 'Удалить запись',

      'about.title': 'Что делает POSBON?',
      'about.apps_title': 'Оценивает приложения',
      'about.apps_desc':
          'Показывает статус по источнику, разрешениям и базе VirusTotal.',
      'about.files_title': 'Проверяет APK-файлы',
      'about.files_desc':
          'Сканирует APK из папки Download или выбранные вручную.',
      'about.safe_title': 'Posbon Safe',
      'about.safe_desc': 'Защищает пароли и важные логины.',

      'app_detail.trusted_badge': 'В списке доверенных приложений',
      'app_detail.posbon_note': 'Заметка Posbon',
      'app_detail.posbon_note_body':
          'Популярные приложения защищены отдельным списком, чтобы они не становились ложно подозрительными из-за стандартных разрешений.',
      'app_detail.summary_title': 'Итоги проверки',
      'app_detail.permissions_none':
          'Данные о разрешениях загружаются или недоступны',
      'app_detail.vt_dangerous_note':
          'В базе VirusTotal найдено совпадение, поэтому статус сразу отмечен как опасный.',
      'app_detail.checking': 'Проверка',

      'results.location': 'Расположение',
      'results.vt_dangerous': 'Опасно по базе VirusTotal',
      'results.vt_clean': 'VirusTotal не нашёл вредоносных меток',
      'results.vt_not_scanned': 'VirusTotal ещё не проверял',

      'files.size_unknown': 'Размер неизвестен',
      'files.moved': 'Перемещён',
      'files.empty_download': 'APK в папке Download не найдены',
      'files.subtitle_ok_long':
          'Показаны APK из папки Download. Проверку запускаете вы, а фоновый монитор отмечает новые APK.',
      'files.subtitle_no_perm_long':
          'Дайте разрешение на файлы, чтобы увидеть содержимое папки Download.',

      'about.app_trusted_hint': 'Есть в списке популярных приложений',

      'scan.external_queued':
          'Внешний файл принят. Он будет проверен автоматически после выдачи разрешений.',
      'safe.device_unlock_failed':
          'Не удалось разблокировать защитой устройства. Войдите с помощью PIN.',

      'onboarding.1.title': 'Сканер безопасности',
      'onboarding.1.desc':
          'Контролируйте файлы и приложения на устройстве в одном месте и быстро обнаруживайте угрозы.',
      'onboarding.2.title': 'Проверка приложений',
      'onboarding.2.desc':
          'Следите за установленными программами по разрешениям, источнику и уровню риска.',
      'onboarding.3.title': 'Защита файлов',
      'onboarding.3.desc':
          'Отделяйте подозрительные файлы и визуально оценивайте состояние безопасности.',

      'perm.notifications.title': 'Уведомления',
      'perm.notifications.desc':
          'Сразу сообщает вам при обнаружении угрозы.',
      'perm.notifications.granted': 'Уведомления включены',
      'perm.notifications.denied': 'Разрешение на уведомления не дано',

      'perm.files.title': 'Сканирование файлов',
      'perm.files.desc': 'Сканирует Download и выбранные файлы.',
      'perm.files.note_wide':
          'Android {sdk}: запрашивается расширенный доступ к файлам',
      'perm.files.note_std':
          'Android {sdk}: достаточно обычного доступа к хранилищу',
      'perm.files.granted': 'Разрешение на сканирование файлов выдано',
      'perm.files.denied':
          'Для глубокой проверки файлов требуется разрешение',

      'perm.media.title': 'Медиафайлы',
      'perm.media.desc':
          'Проверяет фото, видео и аудиофайлы на безопасность.',
      'perm.media.note_new':
          'В Android 13+ разрешения на медиа выдаются отдельно',
      'perm.media.note_old':
          'На старых Android это работает через разрешение на хранилище',
      'perm.media.granted': 'Сканирование медиафайлов включено',
      'perm.media.denied_new':
          'В этой версии Android разрешение на медиа выдаётся отдельно.',
      'perm.media.denied_old':
          'На этом устройстве доступ к медиа работает через разрешение на хранилище.',

      'perm.monitoring.title': 'Мониторинг',
      'perm.monitoring.desc':
          'Помогает POSBON быстрее работать в фоне.',
      'perm.monitoring.granted':
          'Ограничение оптимизации для мониторинга снято',
      'perm.monitoring.denied':
          'Фоновый мониторинг работает в ограниченном режиме',

      'perm.apps.title': 'Анализ приложений',
      'perm.apps.desc': 'Анализирует список установленных приложений.',
      'perm.apps.note': 'Активировано через Android manifest',
      'perm.apps.already': 'Анализ приложений уже включён',

      'perm.install.title': 'Безопасная установка',
      'perm.install.desc':
          'Проверяет APK через POSBON перед установкой.',
      'perm.install.granted': 'Разрешение для проверки APK выдано',
      'perm.install.denied':
          'Это разрешение нужно для проверки APK перед установкой',
    },

    AppLocale.en: {
      'app.title': 'Posbon',
      'app.subtitle': 'Security panel for your phone',
      'app.name_short': 'POSBON',
      'app.slogan': 'Your phone\'s guardian',

      'nav.home': 'Home',
      'nav.apps': 'Apps',
      'nav.results': 'Results',
      'nav.settings': 'Settings',

      'common.continue': 'Continue',
      'common.cancel': 'Cancel',
      'common.back': 'Back',
      'common.save': 'Save',
      'common.delete': 'Delete',
      'common.copy': 'Copy',
      'common.close': 'Close',
      'common.search': 'Search',
      'common.loading': 'Loading...',
      'common.yes': 'Yes',
      'common.no': 'No',
      'common.agree': 'Agree',
      'common.not_available': 'Unavailable',

      'status.safe': 'Safe',
      'status.suspicious': 'Suspicious',
      'status.dangerous': 'Dangerous',
      'status.all': 'All',

      'home.scan_cta_title': 'Scan your phone in one tap',
      'home.scan_cta_body_empty':
          'Check apps and APK files and see any threats in one place.',
      'home.scan_cta_body_done':
          'If you installed new apps or downloaded APKs, run a fresh scan.',
      'home.scan_launch': 'Start scanning',
      'home.scan_launch_sub': 'Refresh apps, APKs and history',
      'home.pill_main_scan': 'Main scan',
      'home.no_results': 'No results yet',
      'home.results_count': '{n} results found',
      'home.quick_access': 'Quick access',
      'home.files_title': 'Files',
      'home.files_sub': 'Check APK and downloaded files',
      'home.apps_title': 'Apps',
      'home.apps_sub': 'Evaluate installed apps',
      'home.safe_title': 'Posbon Safe',
      'home.safe_sub': 'PIN-protected passwords',
      'home.hint_no_scan':
          'Nothing scanned yet. Tap the button above to start.',
      'home.hint_done': 'Latest results were refreshed this session.',
      'home.scanning_now': 'Scanning',
      'home.scanning_bg': 'Scan is running in background',
      'home.open_scan': 'Open',
      'home.live_monitor': 'Live monitoring enabled',
      'home.live_monitor_off': 'Live monitoring disabled',

      'scan.title': 'Scanning...',
      'scan.progress': '{n} of {t} scanned',
      'scan.hint_background':
          'If the scan takes long, it will continue in background and notify when done.',
      'scan.background_btn': 'Continue in background',
      'scan.background_on': 'Scan continues in background.',
      'scan.notification_title': 'POSBON scan finished',
      'scan.bg_start_title': 'Scan in background',
      'scan.bg_start_body':
          'The scan keeps running in background, you\'ll get a notification.',

      'files.title': 'Files',
      'files.subtitle_ok': 'Showing APKs from the Downloads folder.',
      'files.subtitle_no_perm':
          'Grant file permission to see the Downloads folder.',
      'files.count_found': '{n} APKs found',
      'files.bg_hint':
          'Background monitoring auto-scans newly downloaded APKs.',
      'files.scan_all': 'Scan all',
      'files.pick': 'Pick file',
      'files.permission': 'Grant',
      'files.empty_title': 'No APKs in Downloads',
      'files.empty_desc': 'You can pick an individual APK to scan.',

      'results.title': 'Scan results',
      'results.subtitle': 'Tap a card to see the reasons.',
      'results.empty_title': 'All clear',
      'results.empty_desc': 'No threats detected yet.',
      'results.filter_dangerous_only': 'Only dangerous',
      'results.filter_suspicious_only': 'Only suspicious',
      'results.filter_safe_only': 'Only safe',
      'results.reasons': 'Reasons',
      'results.delete_file': 'Delete file',

      'apps.title': 'Installed apps',
      'apps.search_hint': 'Search apps',

      'app_detail.source': 'Source',
      'app_detail.version': 'Version',
      'app_detail.installed_date': 'Installed on',
      'app_detail.updated_date': 'Updated on',
      'app_detail.risk_level': 'Risk level',
      'app_detail.permissions': 'Permissions',
      'app_detail.deep_scan': 'Deep scan',
      'app_detail.scanning': 'Scanning...',
      'app_detail.uninstall': 'Uninstall app',
      'app_detail.show_more': 'Show more',
      'app_detail.show_less': 'Show less',

      'permissions.title': 'Permissions required',
      'permissions.body':
          'POSBON needs these permissions to monitor your device reliably.',
      'permissions.grant': 'Grant',

      'safe.title_vault': 'Passwords',
      'safe.count_label': '{n} passwords',
      'safe.search_placeholder': 'Search by name or login',
      'safe.add_password': 'Add password',
      'safe.setup_title': 'Keep passwords safe',
      'safe.setup_body':
          'Data stays in your phone\'s secure storage. Set a PIN to unlock.',
      'safe.pin_enter': 'Enter a 4-digit PIN',
      'safe.pin_confirm': 'Re-enter PIN',
      'safe.enable': 'Enable Posbon Safe',
      'safe.locked_title': 'Locked section',
      'safe.locked_body':
          'This is where your Gmail, bank and other key logins live.',
      'safe.unlock_device': 'Unlock with device auth',
      'safe.pin_unlock': 'Enter PIN',
      'safe.pin_unlock_btn': 'Unlock with PIN',
      'safe.new_credential': 'New entry',
      'safe.new_credential_hint': 'Only name and password are required.',
      'safe.field_name': 'Name (service or app)',
      'safe.field_name_helper': 'For example: Gmail, Kapitalbank, Telegram',
      'safe.field_login': 'Login or email',
      'safe.field_login_helper': 'Optional, handy for quick copy.',
      'safe.field_password': 'Password',
      'safe.field_password_helper': 'You can generate a strong password here.',
      'safe.field_note': 'Note',
      'safe.field_note_helper': 'Optional note.',
      'safe.required_badge': 'Required',
      'safe.required_missing': 'Name and password are required.',
      'safe.generator_new': 'New password',
      'safe.generator_length': 'Length: {n} chars',
      'safe.strength_weak': 'Weak',
      'safe.strength_okay': 'Medium',
      'safe.strength_strong': 'Strong',
      'safe.empty_title': 'Posbon Safe is empty',
      'safe.empty_desc': 'Store Gmail, bank and other key logins here.',
      'safe.search_no_results': 'No matches',
      'safe.delete_confirm': 'Delete entry',

      'settings.title': 'Settings',
      'settings.language': 'Language',
      'settings.language_current': 'Current language',
      'settings.premium': 'Premium',
      'settings.premium_desc': 'Extended features (coming soon)',
      'settings.support': 'Support',
      'settings.support_desc': 'Contact us',
      'settings.privacy': 'Privacy policy',
      'settings.privacy_desc': 'Terms of use',
      'settings.monitoring': 'Real-time monitoring',
      'settings.monitoring_desc': 'Auto-scan downloaded files',
      'settings.about': 'About the app',
      'settings.version': 'Version',
      'settings.choose_language': 'Choose language',
      'settings.contact_telegram': 'Telegram',
      'settings.contact_email': 'Email',

      'agreement.title': 'Terms of use',
      'agreement.accept': 'I agree, continue',
      'agreement.checkbox': 'I have read and agree to the terms',
      'agreement.body': '''1. General

The Posbon app helps you check the security of files and apps on your device. By using the app you agree to these terms.

2. Security & privacy

Posbon does not collect or transmit personal data. All processing happens on-device. Only with your consent will the app send an APK hash to the VirusTotal service.

3. License

You are granted a free, non-exclusive license to use the app. Copying, modifying the code or redistribution is prohibited.

4. Final clauses

By using the app you are deemed to have read and accepted these terms.

5. Contacts

Email: mamatovramazon9258@gmail.com
Telegram: https://t.me/Mamatov_Ramazon''',

      'uninstall.failed': 'Could not open the uninstall screen.',

      'scan.error_downloads': 'Error reading Downloads folder: {e}',
      'scan.found_dangerous': 'Dangerous APK detected',
      'scan.found_suspicious': 'Suspicious APK detected',
      'scan.no_apps': 'No apps available to scan',

      'files.prev_in_progress':
          'The new file will be scanned after the current scan finishes.',
      'files.delete_missing': 'File was already deleted or not found.',
      'files.delete_done': 'File deleted.',
      'files.delete_failed': 'Could not delete the file: {e}',
      'files.copied': '{label} copied.',

      'safe.auth_reason': 'Authenticate to unlock Posbon Safe',
      'safe.login': 'Login',
      'safe.password': 'Password',
      'safe.copy': 'Copy',
      'safe.login_not_set': 'Not set',
      'safe.login_none': 'No login added',
      'safe.save': 'Save',
      'safe.saving': 'Saving...',
      'safe.protected_badge': 'Protected',
      'safe.new_login': 'New entry',
      'safe.has_generator': 'Generator included',
      'safe.extra_fields_opt': 'Extra fields are optional',
      'safe.main_info': 'Main info',
      'safe.main_info_hint':
          'The primary flow is simplified so it\'s clear what to enter first.',
      'safe.category': 'Category',
      'safe.note': 'Note',
      'safe.note_hint': 'Optional note.',
      'safe.new_password_btn': 'New password',
      'safe.extra_fields': 'Extra fields',
      'safe.extra_fields_hint': 'Category and note only when needed.',
      'safe.category_helper':
          'For organization only. Search works by name, so this is optional.',
      'safe.delete_entry': 'Delete entry',

      'about.title': 'What does POSBON do?',
      'about.apps_title': 'Evaluates apps',
      'about.apps_desc':
          'Shows status by source, permissions and the VirusTotal database.',
      'about.files_title': 'Scans APK files',
      'about.files_desc':
          'Scans APKs from the Downloads folder or picked manually.',
      'about.safe_title': 'Posbon Safe',
      'about.safe_desc': 'Protects passwords and important logins.',

      'app_detail.trusted_badge': 'In the trusted apps list',
      'app_detail.posbon_note': 'Posbon note',
      'app_detail.posbon_note_body':
          'Popular apps are protected by a separate list so their default permissions don\'t make them falsely suspicious.',
      'app_detail.summary_title': 'Scan summary',
      'app_detail.permissions_none':
          'Permission data is loading or not available',
      'app_detail.vt_dangerous_note':
          'A match was found in the VirusTotal database, so the status was marked dangerous directly.',
      'app_detail.checking': 'Scanning',

      'results.location': 'Location',
      'results.vt_dangerous': 'Dangerous by VirusTotal',
      'results.vt_clean': 'VirusTotal found no malicious markers',
      'results.vt_not_scanned': 'Not yet scanned by VirusTotal',

      'files.size_unknown': 'Size unknown',
      'files.moved': 'Moved',
      'files.empty_download': 'No APKs in Downloads folder',
      'files.subtitle_ok_long':
          'Showing APKs from the Downloads folder. You run the scan yourself; the background monitor tags new APKs as they arrive.',
      'files.subtitle_no_perm_long':
          'Grant file permission to see the full Downloads folder.',

      'about.app_trusted_hint': 'Listed as a popular app',

      'scan.external_queued':
          'External file received. It will be scanned automatically once permissions are granted.',
      'safe.device_unlock_failed':
          'Device authentication failed. Try signing in with your PIN.',

      'onboarding.1.title': 'Security scanner',
      'onboarding.1.desc':
          'Monitor files and apps on your device in one place and spot threats quickly.',
      'onboarding.2.title': 'App inspection',
      'onboarding.2.desc':
          'Track installed apps by permissions, source and risk level.',
      'onboarding.3.title': 'File protection',
      'onboarding.3.desc':
          'Isolate suspicious files and visually evaluate your security state.',

      'perm.notifications.title': 'Notifications',
      'perm.notifications.desc': 'Alerts you immediately when a threat is found.',
      'perm.notifications.granted': 'Notifications enabled',
      'perm.notifications.denied': 'Notification permission denied',

      'perm.files.title': 'File scanning',
      'perm.files.desc': 'Scans Downloads and picked files.',
      'perm.files.note_wide': 'Android {sdk}: broad file access is requested',
      'perm.files.note_std':
          'Android {sdk}: standard storage permission is enough',
      'perm.files.granted': 'File scanning permission granted',
      'perm.files.denied':
          'Deep file scanning requires this permission',

      'perm.media.title': 'Media files',
      'perm.media.desc':
          'Looks at images, videos and audio for safety.',
      'perm.media.note_new':
          'On Android 13+, media permissions are managed separately',
      'perm.media.note_old':
          'On older Androids this works via the storage permission',
      'perm.media.granted': 'Media scanning enabled',
      'perm.media.denied_new':
          'On this Android version media permission is managed separately.',
      'perm.media.denied_old':
          'On this device media access works via the storage permission.',

      'perm.monitoring.title': 'Monitoring',
      'perm.monitoring.desc':
          'Helps POSBON work faster in the background.',
      'perm.monitoring.granted':
          'Optimization restriction lifted for monitoring',
      'perm.monitoring.denied':
          'Background monitoring runs in a restricted mode',

      'perm.apps.title': 'App inspection',
      'perm.apps.desc': 'Analyzes the list of installed apps.',
      'perm.apps.note': 'Enabled via Android manifest',
      'perm.apps.already': 'App inspection is already enabled',

      'perm.install.title': 'Safe install',
      'perm.install.desc':
          'Scans APKs via POSBON before installation.',
      'perm.install.granted': 'APK scanning permission granted',
      'perm.install.denied':
          'This permission is required to scan APKs before install',
    },
  };

  static AppStrings of(AppLocale locale) =>
      AppStrings._(_data[locale] ?? _data[AppLocale.uz]!);
}

class LocaleController extends ChangeNotifier {
  LocaleController([AppLocale initial = AppLocale.uz]) : _locale = initial;

  AppLocale _locale;
  AppLocale get locale => _locale;

  AppStrings get strings => AppStrings.of(_locale);

  void set(AppLocale locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
  }
}

class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    required LocaleController super.notifier,
    required super.child,
    super.key,
  });

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope?.notifier != null, 'No LocaleScope found in context');
    return scope!.notifier!;
  }

  static AppStrings stringsOf(BuildContext context) => of(context).strings;
}

extension LocaleContextExt on BuildContext {
  AppStrings get tr => LocaleScope.stringsOf(this);
  LocaleController get localeController => LocaleScope.of(this);
}

String formatTemplate(String template, Map<String, Object?> values) {
  var result = template;
  values.forEach((key, value) {
    result = result.replaceAll('{$key}', value?.toString() ?? '');
  });
  return result;
}
