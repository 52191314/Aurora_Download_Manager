#!/usr/bin/env python
"""
Add localization keys addressing F-Droid MR !45273 note #4003001104.
- Fixes 'mehere' typo in app_de.arb
- Adds:
  - pasteLink
  - sortFieldDate, sortFieldName, sortFieldSize, sortFieldPriority, sortFieldState, sortFieldSpeed
  - batteryOptDialogTitle, batteryOptDialogContent, btnNeverAskAgain, btnLater, btnOpenSettings
  - linkRefreshNeededTitle, linkRefreshNeededDesc (template), linkRefreshFailedRepeatedly, linkRefreshPrompt, btnOpenInBrowser, btnRefreshAutomatically
  - settingsSearchSuggestions, settingsSearchSuggestionsDesc
"""
import json
import os

BASE = r"E:/02_Projects/Aurora_Download_Manager/lib/l10n"
LOCALES = ['en', 'ar', 'de', 'es', 'fr', 'hi', 'id', 'ja', 'pt', 'ru', 'zh']

NEW_KEYS = {
  'en': {
    'pasteLink': 'Paste link',
    'sortFieldDate': 'Date',
    'sortFieldName': 'Name',
    'sortFieldSize': 'Size',
    'sortFieldPriority': 'Priority',
    'sortFieldState': 'State',
    'sortFieldSpeed': 'Speed',
    'batteryOptDialogTitle': 'Battery Optimization',
    'batteryOptDialogContent': 'Aurora Downloader requires background execution permission to ensure uninterrupted downloads.\n\nWould you like to exclude Aurora from battery optimization?',
    'btnNeverAskAgain': 'Never ask again',
    'btnLater': 'Later',
    'btnOpenSettings': 'Open settings',
    'linkRefreshNeededTitle': 'Link Refresh Needed',
    'linkRefreshNeededDesc': '"{name}" could not complete after multiple attempts.',
    'linkRefreshFailedRepeatedly': 'Download failed repeatedly (expired link or network block).',
    'linkRefreshPrompt': 'Would you like to attempt an automatic background refresh or open the source page in the browser?',
    'btnOpenInBrowser': 'Open in Browser',
    'btnRefreshAutomatically': 'Refresh Automatically',
    'settingsSearchSuggestions': 'Search suggestions',
    'settingsSearchSuggestionsDesc': 'Fetch suggestions from search engine while typing in the address bar',
  },
  'de': {
    'pasteLink': 'Link einfügen',
    'sortFieldDate': 'Datum',
    'sortFieldName': 'Name',
    'sortFieldSize': 'Größe',
    'sortFieldPriority': 'Priorität',
    'sortFieldState': 'Status',
    'sortFieldSpeed': 'Geschwindigkeit',
    'batteryOptDialogTitle': 'Akku-Optimierung',
    'batteryOptDialogContent': 'Aurora Downloader benötigt die Berechtigung zur Ausführung im Hintergrund, um unterbrechungsfreie Downloads zu gewährleisten.\n\nMöchten Sie Aurora von der Akku-Optimierung ausschließen?',
    'btnNeverAskAgain': 'Nicht mehr nachfragen',
    'btnLater': 'Später',
    'btnOpenSettings': 'Einstellungen öffnen',
    'linkRefreshNeededTitle': 'Link-Aktualisierung erforderlich',
    'linkRefreshNeededDesc': '„{name}“ konnte nach mehreren Versuchen nicht abgeschlossen werden.',
    'linkRefreshFailedRepeatedly': 'Download ist wiederholt fehlgeschlagen (abgelaufener Link oder Netzwerkblockierung).',
    'linkRefreshPrompt': 'Möchten Sie eine automatische Aktualisierung im Hintergrund versuchen oder die Quellseite im Browser öffnen?',
    'btnOpenInBrowser': 'Im Browser öffnen',
    'btnRefreshAutomatically': 'Automatisch aktualisieren',
    'settingsSearchSuggestions': 'Suchvorschläge',
    'settingsSearchSuggestionsDesc': 'Vorschläge von der Suchmaschine beim Tippen in der Adressleiste abrufen',
  },
  'fr': {
    'pasteLink': 'Coller le lien',
    'sortFieldDate': 'Date',
    'sortFieldName': 'Nom',
    'sortFieldSize': 'Taille',
    'sortFieldPriority': 'Priorité',
    'sortFieldState': 'État',
    'sortFieldSpeed': 'Vitesse',
    'batteryOptDialogTitle': 'Optimisation de la batterie',
    'batteryOptDialogContent': 'Aurora Downloader nécessite l\'autorisation d\'exécution en arrière-plan pour garantir des téléchargements ininterrompus.\n\nSouhaitez-vous exclure Aurora de l\'optimisation de la batterie ?',
    'btnNeverAskAgain': 'Ne plus demander',
    'btnLater': 'Plus tard',
    'btnOpenSettings': 'Ouvrir les paramètres',
    'linkRefreshNeededTitle': 'Actualisation du lien requise',
    'linkRefreshNeededDesc': '« {name} » n\'a pas pu se terminer après plusieurs tentatives.',
    'linkRefreshFailedRepeatedly': 'Le téléchargement a échoué à plusieurs reprises (lien expiré ou blocage réseau).',
    'linkRefreshPrompt': 'Souhaitez-vous tenter une actualisation automatique en arrière-plan ou ouvrir la page source dans le navigateur ?',
    'btnOpenInBrowser': 'Ouvrir dans le navigateur',
    'btnRefreshAutomatically': 'Actualiser automatiquement',
    'settingsSearchSuggestions': 'Suggestions de recherche',
    'settingsSearchSuggestionsDesc': 'Obtenir des suggestions du moteur de recherche lors de la saisie dans la barre d\'adresse',
  },
  'es': {
    'pasteLink': 'Pegar enlace',
    'sortFieldDate': 'Fecha',
    'sortFieldName': 'Nombre',
    'sortFieldSize': 'Tamaño',
    'sortFieldPriority': 'Prioridad',
    'sortFieldState': 'Estado',
    'sortFieldSpeed': 'Velocidad',
    'batteryOptDialogTitle': 'Optimización de batería',
    'batteryOptDialogContent': 'Aurora Downloader requiere permiso de ejecución en segundo plano para garantizar descargas ininterrumpidas.\n\n¿Desea excluir Aurora de la optimización de batería?',
    'btnNeverAskAgain': 'No volver a preguntar',
    'btnLater': 'Más tarde',
    'btnOpenSettings': 'Abrir ajustes',
    'linkRefreshNeededTitle': 'Actualización de enlace necesaria',
    'linkRefreshNeededDesc': '"{name}" no pudo completarse después de varios intentos.',
    'linkRefreshFailedRepeatedly': 'La descarga falló repetidamente (enlace caducado o bloqueo de red).',
    'linkRefreshPrompt': '¿Desea intentar una actualización automática en segundo plano o abrir la página de origen en el navegador?',
    'btnOpenInBrowser': 'Abrir en el navegador',
    'btnRefreshAutomatically': 'Actualizar automáticamente',
    'settingsSearchSuggestions': 'Sugerencias de búsqueda',
    'settingsSearchSuggestionsDesc': 'Obtener sugerencias del motor de búsqueda al escribir en la barra de direcciones',
  },
  'pt': {
    'pasteLink': 'Colar link',
    'sortFieldDate': 'Data',
    'sortFieldName': 'Nome',
    'sortFieldSize': 'Tamanho',
    'sortFieldPriority': 'Prioridade',
    'sortFieldState': 'Status',
    'sortFieldSpeed': 'Velocidade',
    'batteryOptDialogTitle': 'Otimização de bateria',
    'batteryOptDialogContent': 'O Aurora Downloader precisa de permissão de execução em segundo plano para garantir downloads ininterruptos.\n\nDeseja excluir o Aurora da otimização de bateria?',
    'btnNeverAskAgain': 'Não perguntar novamente',
    'btnLater': 'Mais tarde',
    'btnOpenSettings': 'Abrir configurações',
    'linkRefreshNeededTitle': 'Atualização de link necessária',
    'linkRefreshNeededDesc': '"{name}" não pôde ser concluído após várias tentativas.',
    'linkRefreshFailedRepeatedly': 'O download falhou repetidamente (link expirado ou bloqueio de rede).',
    'linkRefreshPrompt': 'Deseja tentar uma atualização automática em segundo plano ou abrir a página de origem no navegador?',
    'btnOpenInBrowser': 'Abrir no navegador',
    'btnRefreshAutomatically': 'Atualizar automaticamente',
    'settingsSearchSuggestions': 'Sugestões de pesquisa',
    'settingsSearchSuggestionsDesc': 'Obter sugestões do mecanismo de pesquisa ao digitar na barra de endereços',
  },
  'ru': {
    'pasteLink': 'Вставить ссылку',
    'sortFieldDate': 'Дата',
    'sortFieldName': 'Имя',
    'sortFieldSize': 'Размер',
    'sortFieldPriority': 'Приоритет',
    'sortFieldState': 'Статус',
    'sortFieldSpeed': 'Скорость',
    'batteryOptDialogTitle': 'Оптимизация батареи',
    'batteryOptDialogContent': 'Aurora Downloader требует разрешения на работу в фоновом режиме для бесперебойной загрузки.\n\nИсключить Aurora из оптимизации батареи?',
    'btnNeverAskAgain': 'Больше не спрашивать',
    'btnLater': 'Позже',
    'btnOpenSettings': 'Открыть настройки',
    'linkRefreshNeededTitle': 'Требуется обновить ссылку',
    'linkRefreshNeededDesc': 'Не удалось завершить загрузку «{name}» после нескольких попыток.',
    'linkRefreshFailedRepeatedly': 'Загрузка неоднократно завершалась сбоем (истёк срок ссылки или блокировка сети).',
    'linkRefreshPrompt': 'Попытаться обновить ссылку автоматически в фоне или открыть исходную страницу в браузере?',
    'btnOpenInBrowser': 'Открыть в браузере',
    'btnRefreshAutomatically': 'Обновить автоматически',
    'settingsSearchSuggestions': 'Поисковые подсказки',
    'settingsSearchSuggestionsDesc': 'Получать подсказки от поисковой системы при вводе в адресной строке',
  },
  'id': {
    'pasteLink': 'Tempel tautan',
    'sortFieldDate': 'Tanggal',
    'sortFieldName': 'Nama',
    'sortFieldSize': 'Ukuran',
    'sortFieldPriority': 'Prioritas',
    'sortFieldState': 'Status',
    'sortFieldSpeed': 'Kecepatan',
    'batteryOptDialogTitle': 'Optimalisasi Baterai',
    'batteryOptDialogContent': 'Aurora Downloader memerlukan izin eksekusi latar belakang untuk memastikan unduhan tidak terputus.\n\nApakah Anda ingin mengecualikan Aurora dari pengoptimalan baterai?',
    'btnNeverAskAgain': 'Jangan tanya lagi',
    'btnLater': 'Nanti',
    'btnOpenSettings': 'Buka pengaturan',
    'linkRefreshNeededTitle': 'Pembaruan Tautan Diperlukan',
    'linkRefreshNeededDesc': '"{name}" tidak dapat diselesaikan setelah beberapa kali mencoba.',
    'linkRefreshFailedRepeatedly': 'Pengunduhan berulang kali gagal (tautan kedaluwarsa atau pemblokiran jaringan).',
    'linkRefreshPrompt': 'Apakah Anda ingin mencoba penyegaran latar belakang otomatis atau membuka halaman sumber di browser?',
    'btnOpenInBrowser': 'Buka di Browser',
    'btnRefreshAutomatically': 'Segarkan Otomatis',
    'settingsSearchSuggestions': 'Saran penelusuran',
    'settingsSearchSuggestionsDesc': 'Ambil saran dari mesin telusur saat mengetik di bilah alamat',
  },
  'ja': {
    'pasteLink': 'リンクを貼り付け',
    'sortFieldDate': '日付',
    'sortFieldName': '名前',
    'sortFieldSize': 'サイズ',
    'sortFieldPriority': '優先度',
    'sortFieldState': '状態',
    'sortFieldSpeed': '速度',
    'batteryOptDialogTitle': 'バッテリーの最適化',
    'batteryOptDialogContent': 'ダウンロードを中断なく完了するために、Aurora Downloaderのバックグラウンド実行権限が必要です。\n\nAuroraをバッテリー最適化から除外しますか？',
    'btnNeverAskAgain': '今後確認しない',
    'btnLater': '後で',
    'btnOpenSettings': '設定を開く',
    'linkRefreshNeededTitle': 'リンクの更新が必要です',
    'linkRefreshNeededDesc': '複数回試行しましたが「{name}」を完了できませんでした。',
    'linkRefreshFailedRepeatedly': 'ダウンロードが繰り返し失敗しました（リンクの期限切れまたはネットワーク制限）。',
    'linkRefreshPrompt': 'バックグラウンドで自動更新を試行しますか？それともブラウザで元のページを開きますか？',
    'btnOpenInBrowser': 'ブラウザで開く',
    'btnRefreshAutomatically': '自動更新',
    'settingsSearchSuggestions': '検索の候補',
    'settingsSearchSuggestionsDesc': 'アドレスバーに入力中に検索エンジンから候補を取得する',
  },
  'ar': {
    'pasteLink': 'لصق الرابط',
    'sortFieldDate': 'التاريخ',
    'sortFieldName': 'الاسم',
    'sortFieldSize': 'الحجم',
    'sortFieldPriority': 'الأولوية',
    'sortFieldState': 'الحالة',
    'sortFieldSpeed': 'السرعة',
    'batteryOptDialogTitle': 'تحسين البطارية',
    'batteryOptDialogContent': 'يتطلب Aurora Downloader إذن التشغيل في الخلفية لضمان تنزيلات دون انقطاع.\n\nهل ترغب في استبعاد Aurora من تحسين البطارية؟',
    'btnNeverAskAgain': 'عدم السؤال مرة أخرى',
    'btnLater': 'لاحقًا',
    'btnOpenSettings': 'فتح الإعدادات',
    'linkRefreshNeededTitle': 'مطلوب تحديث الرابط',
    'linkRefreshNeededDesc': 'تعذر إكمال "{name}" بعد عدة محاولات.',
    'linkRefreshFailedRepeatedly': 'فشل التنزيل بشكل متكرر (رابط منتهي الصلاحية أو حظر في الشبكة).',
    'linkRefreshPrompt': 'هل ترغب في محاولة التحديث التلقائي في الخلفية أو فتح صفحة المصدر في المتصفح؟',
    'btnOpenInBrowser': 'فتح في المتصفح',
    'btnRefreshAutomatically': 'تحديث تلقائي',
    'settingsSearchSuggestions': 'اقتراحات البحث',
    'settingsSearchSuggestionsDesc': 'جلب الاقتراحات من محرك البحث أثناء الكتابة في شريط العناوين',
  },
  'hi': {
    'pasteLink': 'लिंक पेस्ट करें',
    'sortFieldDate': 'दिनांक',
    'sortFieldName': 'नाम',
    'sortFieldSize': 'आकार',
    'sortFieldPriority': 'प्राथमिकता',
    'sortFieldState': 'स्थिति',
    'sortFieldSpeed': 'गति',
    'batteryOptDialogTitle': 'बैटरी अनुकूलन',
    'batteryOptDialogContent': 'डाउनलोड को निर्बाध रखने के लिए Aurora Downloader को बैकग्राउंड अनुमति चाहिए।\n\nक्या आप Aurora को बैटरी अनुकूलन से बाहर रखना चाहते हैं?',
    'btnNeverAskAgain': 'फिर कभी न पूछें',
    'btnLater': 'बाद में',
    'btnOpenSettings': 'सेटिंग्स खोलें',
    'linkRefreshNeededTitle': 'लिंक रीफ्रेश आवश्यक',
    'linkRefreshNeededDesc': 'कई प्रयासों के बाद भी "{name}" पूरा नहीं हो सका।',
    'linkRefreshFailedRepeatedly': 'डाउनलोड बार-बार विफल रहा (लिंक समाप्त या नेटवर्क अवरोध)।',
    'linkRefreshPrompt': 'क्या आप पृष्ठभूमि में स्वचालित रीफ्रेश का प्रयास करना चाहते हैं या ब्राउज़र में स्रोत पृष्ठ खोलना चाहते हैं?',
    'btnOpenInBrowser': 'ब्राउज़र में खोलें',
    'btnRefreshAutomatically': 'स्वचालित रूप से रीफ्रेश करें',
    'settingsSearchSuggestions': 'खोज सुझाव',
    'settingsSearchSuggestionsDesc': 'एड्रेस बार में टाइप करते समय खोज इंजन से सुझाव प्राप्त करें',
  },
  'zh': {
    'pasteLink': '粘贴链接',
    'sortFieldDate': '日期',
    'sortFieldName': '名称',
    'sortFieldSize': '大小',
    'sortFieldPriority': '优先级',
    'sortFieldState': '状态',
    'sortFieldSpeed': '速度',
    'batteryOptDialogTitle': '电池优化',
    'batteryOptDialogContent': 'Aurora Downloader 需要后台运行权限以确保下载不中断。\n\n是否将 Aurora 排除在电池优化之外？',
    'btnNeverAskAgain': '不再询问',
    'btnLater': '稍后',
    'btnOpenSettings': '打开设置',
    'linkRefreshNeededTitle': '需要刷新链接',
    'linkRefreshNeededDesc': '经过多次尝试仍无法完成“{name}”。',
    'linkRefreshFailedRepeatedly': '下载多次失败（链接已过期或网络受阻）。',
    'linkRefreshPrompt': '您要尝试在后台自动刷新，还是在浏览器中打开源页面？',
    'btnOpenInBrowser': '在浏览器中打开',
    'btnRefreshAutomatically': '自动刷新',
    'settingsSearchSuggestions': '搜索建议',
    'settingsSearchSuggestionsDesc': '在地址栏中输入时从搜索引擎获取联想建议',
  },
}

TEMPLATE_META = {
  'linkRefreshNeededDesc': {'placeholders': {'name': {'type': 'String'}}},
}

def main():
    # 1. Update app_de.arb typo
    de_path = os.path.join(BASE, 'app_de.arb')
    with open(de_path, 'r', encoding='utf-8') as f:
        de_data = json.load(f)
    if 'onboardingStep4Desc' in de_data and 'mehere' in de_data['onboardingStep4Desc']:
        de_data['onboardingStep4Desc'] = de_data['onboardingStep4Desc'].replace('mehere', 'mehrere')
        print("Fixed typo in app_de.arb onboardingStep4Desc: mehere -> mehrere")
        with open(de_path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(de_data, f, ensure_ascii=False, indent=2)
            f.write('\n')

    # 2. Add keys across all locales
    for loc in LOCALES:
        path = os.path.join(BASE, f'app_{loc}.arb')
        with open(path, 'r', encoding='utf-8') as f:
            d = json.load(f)
        added = 0
        for k, v in NEW_KEYS[loc].items():
            if k not in d:
                d[k] = v
                added += 1
            else:
                d[k] = v  # update if needed
        if loc == 'en':
            for k, meta in TEMPLATE_META.items():
                d['@' + k] = meta
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f"{loc}: updated/added {added} keys in {path}")

if __name__ == '__main__':
    main()
