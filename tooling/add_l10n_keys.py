#!/usr/bin/env python
"""Add 11 new l10n keys to all 11 app_*.arb files (OSS repo).

Keys: addToDownloadQueue, fromLabel, linkLabel, priorityLabel,
cardPriorityMedium, loadingQuality, downloadLater, filenameLongWarning (tpl),
snifferDlgClearSiteDataHost (tpl), snifferDlgClearSiteDataThis,
settingsScheduledEmptyHint.
"""
import json, sys

BASE = r'E:/02_Projects/aurora_downloader_oss/lib/l10n'
LOCALES = ['en', 'ar', 'de', 'es', 'fr', 'hi', 'id', 'ja', 'pt', 'ru', 'zh']

NEW = {
 'en': {
  'addToDownloadQueue': 'Add to Download Queue',
  'fromLabel': 'From',
  'linkLabel': 'Link',
  'priorityLabel': 'Priority',
  'cardPriorityMedium': 'Medium',
  'loadingQuality': 'Loading quality options...',
  'downloadLater': 'Download later',
  'filenameLongWarning': "Filename is long and was auto-truncated to fit Android's {limit}-byte file-name limit. You can rename it, or keep this name.",
  'snifferDlgClearSiteDataHost': 'Clear cookies, localStorage, and cache for {host}?',
  'snifferDlgClearSiteDataThis': 'Clear cookies, localStorage, and cache for this site?',
  'settingsScheduledEmptyHint': 'Add a download and choose "Download later" to schedule it here.',
 },
 'fr': {
  'addToDownloadQueue': 'Ajouter à la file de téléchargement',
  'fromLabel': 'De',
  'linkLabel': 'Lien',
  'priorityLabel': 'Priorité',
  'cardPriorityMedium': 'Moyenne',
  'loadingQuality': 'Chargement des options de qualité…',
  'downloadLater': 'Télécharger plus tard',
  'filenameLongWarning': "Le nom de fichier est long et a été tronqué automatiquement pour respecter la limite de {limit} octets d'Android. Vous pouvez le renommer ou conserver ce nom.",
  'snifferDlgClearSiteDataHost': 'Effacer les cookies, le stockage local et le cache de {host} ?',
  'snifferDlgClearSiteDataThis': 'Effacer les cookies, le stockage local et le cache de ce site ?',
  'settingsScheduledEmptyHint': 'Ajoutez un téléchargement et choisissez « Télécharger plus tard » pour le planifier ici.',
 },
 'de': {
  'addToDownloadQueue': 'Zur Download-Warteschlange hinzufügen',
  'fromLabel': 'Von',
  'linkLabel': 'Link',
  'priorityLabel': 'Priorität',
  'cardPriorityMedium': 'Mittel',
  'loadingQuality': 'Qualitätsoptionen werden geladen…',
  'downloadLater': 'Später herunterladen',
  'filenameLongWarning': 'Der Dateiname ist lang und wurde automatisch gekürzt, um das {limit}-Byte-Limit von Android einzuhalten. Sie können ihn umbenennen oder diesen Namen behalten.',
  'snifferDlgClearSiteDataHost': 'Cookies, lokalen Speicher und Cache für {host} löschen?',
  'snifferDlgClearSiteDataThis': 'Cookies, lokalen Speicher und Cache für diese Website löschen?',
  'settingsScheduledEmptyHint': 'Fügen Sie einen Download hinzu und wählen Sie „Später herunterladen“, um ihn hier zu planen.',
 },
 'es': {
  'addToDownloadQueue': 'Agregar a la cola de descargas',
  'fromLabel': 'De',
  'linkLabel': 'Enlace',
  'priorityLabel': 'Prioridad',
  'cardPriorityMedium': 'Media',
  'loadingQuality': 'Cargando opciones de calidad…',
  'downloadLater': 'Descargar más tarde',
  'filenameLongWarning': 'El nombre de archivo es largo y se truncó automáticamente para ajustarse al límite de {limit} bytes de Android. Puedes renombrarlo o conservar este nombre.',
  'snifferDlgClearSiteDataHost': '¿Borrar cookies, almacenamiento local y caché de {host}?',
  'snifferDlgClearSiteDataThis': '¿Borrar cookies, almacenamiento local y caché de este sitio?',
  'settingsScheduledEmptyHint': 'Añade una descarga y elige «Descargar más tarde» para programarla aquí.',
 },
 'pt': {
  'addToDownloadQueue': 'Adicionar à fila de downloads',
  'fromLabel': 'De',
  'linkLabel': 'Link',
  'priorityLabel': 'Prioridade',
  'cardPriorityMedium': 'Média',
  'loadingQuality': 'Carregando opções de qualidade…',
  'downloadLater': 'Baixar mais tarde',
  'filenameLongWarning': 'O nome do arquivo é longo e foi truncado automaticamente para caber no limite de {limit} bytes do Android. Você pode renomeá-lo ou manter este nome.',
  'snifferDlgClearSiteDataHost': 'Limpar cookies, armazenamento local e cache de {host}?',
  'snifferDlgClearSiteDataThis': 'Limpar cookies, armazenamento local e cache deste site?',
  'settingsScheduledEmptyHint': 'Adicione um download e escolha "Baixar mais tarde" para agendá-lo aqui.',
 },
 'ru': {
  'addToDownloadQueue': 'Добавить в очередь загрузок',
  'fromLabel': 'Из',
  'linkLabel': 'Ссылка',
  'priorityLabel': 'Приоритет',
  'cardPriorityMedium': 'Средний',
  'loadingQuality': 'Загрузка параметров качества…',
  'downloadLater': 'Скачать позже',
  'filenameLongWarning': 'Имя файла слишком длинное и было автоматически сокращено до лимита Android в {limit} байт. Вы можете переименовать его или оставить это имя.',
  'snifferDlgClearSiteDataHost': 'Очистить файлы cookie, локальное хранилище и кеш для {host}?',
  'snifferDlgClearSiteDataThis': 'Очистить файлы cookie, локальное хранилище и кеш для этого сайта?',
  'settingsScheduledEmptyHint': 'Добавьте загрузку и выберите «Скачать позже», чтобы запланировать её здесь.',
 },
 'id': {
  'addToDownloadQueue': 'Tambahkan ke antrean unduhan',
  'fromLabel': 'Dari',
  'linkLabel': 'Tautan',
  'priorityLabel': 'Prioritas',
  'cardPriorityMedium': 'Sedang',
  'loadingQuality': 'Memuat opsi kualitas…',
  'downloadLater': 'Unduh nanti',
  'filenameLongWarning': 'Nama file panjang dan dipotong otomatis agar sesuai batas {limit} byte Android. Anda dapat mengganti namanya atau mempertahankan nama ini.',
  'snifferDlgClearSiteDataHost': 'Hapus cookie, penyimpanan lokal, dan cache untuk {host}?',
  'snifferDlgClearSiteDataThis': 'Hapus cookie, penyimpanan lokal, dan cache untuk situs ini?',
  'settingsScheduledEmptyHint': 'Tambahkan unduhan dan pilih "Unduh nanti" untuk menjadwalkannya di sini.',
 },
 'ja': {
  'addToDownloadQueue': 'ダウンロードキューに追加',
  'fromLabel': '送信元',
  'linkLabel': 'リンク',
  'priorityLabel': '優先度',
  'cardPriorityMedium': '中',
  'loadingQuality': '品質オプションを読み込み中…',
  'downloadLater': '後でダウンロード',
  'filenameLongWarning': 'ファイル名が長いため、Androidの{limit}バイト制限に合わせて自動的に短縮されました。名前を変更するか、この名前を維持できます。',
  'snifferDlgClearSiteDataHost': '{host} のCookie、ローカルストレージ、キャッシュを削除しますか？',
  'snifferDlgClearSiteDataThis': 'このサイトのCookie、ローカルストレージ、キャッシュを削除しますか？',
  'settingsScheduledEmptyHint': 'ダウンロードを追加して「後でダウンロード」を選ぶと、ここでスケジュールできます。',
 },
 'zh': {
  'addToDownloadQueue': '添加到下载队列',
  'fromLabel': '来自',
  'linkLabel': '链接',
  'priorityLabel': '优先级',
  'cardPriorityMedium': '中',
  'loadingQuality': '正在加载质量选项…',
  'downloadLater': '稍后下载',
  'filenameLongWarning': '文件名过长，已自动截断以符合 Android 的 {limit} 字节限制。您可以重命名，或保留此名称。',
  'snifferDlgClearSiteDataHost': '清除 {host} 的 Cookie、本地存储和缓存？',
  'snifferDlgClearSiteDataThis': '清除此网站的 Cookie、本地存储和缓存？',
  'settingsScheduledEmptyHint': '添加下载并选择“稍后下载”，即可在此安排计划。',
 },
 'hi': {
  'addToDownloadQueue': 'डाउनलोड कतार में जोड़ें',
  'fromLabel': 'से',
  'linkLabel': 'लिंक',
  'priorityLabel': 'प्राथमिकता',
  'cardPriorityMedium': 'मध्यम',
  'loadingQuality': 'गुणवत्ता विकल्प लोड हो रहे हैं…',
  'downloadLater': 'बाद में डाउनलोड करें',
  'filenameLongWarning': 'फ़ाइल नाम लंबा है और Android की {limit} बाइट सीमा में फिट होने के लिए इसे स्वतः छोटा किया गया। आप इसका नाम बदल सकते हैं या यह नाम रख सकते हैं।',
  'snifferDlgClearSiteDataHost': '{host} के कुकीज़, स्थानीय संग्रहण और कैश साफ़ करें?',
  'snifferDlgClearSiteDataThis': 'इस साइट के कुकीज़, स्थानीय संग्रहण और कैश साफ़ करें?',
  'settingsScheduledEmptyHint': 'एक डाउनलोड जोड़ें और इसे यहाँ शेड्यूल करने के लिए "बाद में डाउनलोड करें" चुनें।',
 },
 'ar': {
  'addToDownloadQueue': 'إضافة إلى قائمة التنزيل',
  'fromLabel': 'من',
  'linkLabel': 'رابط',
  'priorityLabel': 'الأولوية',
  'cardPriorityMedium': 'متوسط',
  'loadingQuality': 'جارٍ تحميل خيارات الجودة…',
  'downloadLater': 'التنزيل لاحقًا',
  'filenameLongWarning': 'اسم الملف طويل وتم اقتطاعه تلقائيًا ليتناسب مع حد Android البالغ {limit} بايت. يمكنك إعادة تسميته أو الاحتفاظ بهذا الاسم.',
  'snifferDlgClearSiteDataHost': 'مسح ملفات تعريف الارتباط والتخزين المحلي وذاكرة التخزين المؤقت لـ {host}؟',
  'snifferDlgClearSiteDataThis': 'مسح ملفات تعريف الارتباط والتخزين المحلي وذاكرة التخزين المؤقت لهذا الموقع؟',
  'settingsScheduledEmptyHint': 'أضف تنزيلًا واختر «التنزيل لاحقًا» لجدولته هنا.',
 },
}

TEMPLATE_META = {
 'filenameLongWarning': {'placeholders': {'limit': {'type': 'int'}}},
 'snifferDlgClearSiteDataHost': {'placeholders': {'host': {'type': 'String'}}},
}

if len(sys.argv) > 1:
    BASE = sys.argv[1]

for loc in LOCALES:
    path = f'{BASE}/app_{loc}.arb'
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    for k, v in NEW[loc].items():
        assert k not in d, f'{k} already present in {path}'
        d[k] = v
    if loc == 'en':
        for k, meta in TEMPLATE_META.items():
            d['@' + k] = meta
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'{path}: +{len(NEW[loc])} keys')
print('DONE')
