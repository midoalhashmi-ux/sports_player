/// جافاسكربت مُحقَن داخل WebView — مفصول عن منطق Dart.
///
/// كان ~930 سطراً مدفونة كنصوص خام داخل `watch_screen_discovery.dart`
/// (ثلث الملف، كتلة واحدة منها 547 سطراً). الفصل هنا **لا يغيّر أي سلوك
/// إطلاقاً** — نص حرفي منقول كما هو — لكنه يجعل منطق Dart وكود المتصفح
/// قابلَين للقراءة والمراجعة كلٌّ على حدة.
///
/// **قاعدة**: أي تعديل هنا يمس سلوك الصفحة داخل WebView مباشرة — راجع
/// مهارة `stream-debug` وسجل TECHNICAL.md قبل أي تغيير.
library;

/// حماية الصفحة: حجب النوافذ/الإعلانات المقحَمة، تعطيل window.open،
/// رفض أذونات الإشعارات، وتحييد أي تراكب مزيّف — مع استثناء صريح لأي
/// تحدي كابتشا حقيقي (Cloudflare/hCaptcha/reCAPTCHA) ليبقى قابلاً للحل.
const String kWebProtectionScript = r'''(() => {
      try {
        if (window.__sportsPlayerProtectionInstalled) return;
        window.__sportsPlayerProtectionInstalled = true;
        // سجل كل مؤقّت/مراقب نُنشئه هنا، ليقدر kQuiesceScript يوقفها كلها
        // دفعة واحدة بعد نجاح التشغيل الأصلي — راجع تعليقه.
        window.__sportsPlayerTimers = window.__sportsPlayerTimers || [];
        window.__sportsPlayerObservers = window.__sportsPlayerObservers || [];
        const spInterval = (fn, ms) => {
          try { const id = setInterval(fn, ms); window.__sportsPlayerTimers.push(id); return id; } catch (_) { return 0; }
        };
        const spObserve = (observer, target, options) => {
          try { observer.observe(target, options); window.__sportsPlayerObservers.push(observer); } catch (_) {}
        };
        const blocked = (url) => {
          try {
            const u = new URL(url, location.href);
            const h = (u.hostname || '').toLowerCase();
            const p = (u.pathname || '').toLowerCase();
             const raw = String(url || '').toLowerCase();
             if (!/^https?:$/i.test(u.protocol)) return true;
            return /(doubleclick|googlesyndication|googleadservices|adservice|adnxs|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|onclick|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|app-install|push-notification)/i.test(`${h} ${p}`) ||
               /(popup|popunder|clickunder|interstitial|advertisement|ads?\b|otp|one[- ]?time|verification|verify|passcode|pin|subscription|subscribe|phone|mobile|credit[- ]?card|download-app)/i.test(`${p} ${u.search} ${raw}`);
          } catch (_) { return false; }
        };
         const playerLike = (el) => {
           try {
             return !!(el && el.closest && el.closest('video, audio, iframe, .video-js, .jwplayer, .jw-wrapper, .plyr, [class*="player" i], [id*="player" i]'));
           } catch (_) { return false; }
         };
          const humanChallenge = (el) => {
            try {
              if (!el) return false;
              if (el.matches && el.matches('iframe[src*="challenges.cloudflare.com" i],iframe[src*="hcaptcha.com" i],iframe[src*="recaptcha" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha')) return true;
              if (el.querySelector && el.querySelector('iframe[src*="challenges.cloudflare.com" i],iframe[src*="hcaptcha.com" i],iframe[src*="recaptcha" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha')) return true;
              const text = `${el.innerText || ''} ${el.textContent || ''}`.toLowerCase();
              return /verify you are human|checking your browser|complete the security check|verifying you are human|i'?m not a robot|prove you'?re human/.test(text);
            } catch (_) { return false; }
          };
         const sensitivePrompt = (el) => {
           try {
             const text = `${el && el.innerText || ''} ${el && el.textContent || ''} ${el && el.getAttribute && el.getAttribute('placeholder') || ''} ${el && el.getAttribute && el.getAttribute('name') || ''} ${el && el.getAttribute && el.getAttribute('autocomplete') || ''}`.toLowerCase();
             // "روبوت" يغطي إعلانات مقلَّدة بشكل كابتشا عربية ("تأكد أنك لست
             // روبوتاً") — لا يتعارض مع humanChallenge() لأن هذا الأخير يفحص
             // أولاً وجود ودجت كابتشا حقيقي (Cloudflare/hCaptcha/reCAPTCHA)
             // ويستثنيه قبل ما توصل هذي القائمة أصلاً.
             // "انقر للمزيد للمتابعة"/"انتباه" — إعلان مقلَّد بشكل نافذة نظام
             // (سكرين شوت فعلي من المستخدم: عنوان "انتباه" + زر "أكثر"/"إغلاق")
             // فوق مشغّل vidtube/JWPlayer. "انتباه" وحدها آمنة هنا لأنها لا
             // تصل هذا الفحص أصلاً إلا على عنصر مطابق مسبقاً لمحدِّد
             // popup/dialog أو بفحص الحجم/الموضع الديناميكي (راجع
             // hideUnsafePrompts أدناه) — لا فحص عام على كل نص الصفحة.
             return /(otp|one[- ]?time|verification|verify|passcode|pin|sms|phone|mobile|رقم الهاتف|رمز|رسالة نصية|اشتراك|subscribe|subscription|install app|تنزيل التطبيق|روبوت|لست إنسان|لست انسان|التحقق الأمني|انتباه|انقر للمزيد|للمتابعة)/i.test(text);
           } catch (_) { return false; }
         };
         const adLike = (el) => {
           try {
             if (!el) return false;
             const text = `${el.id || ''} ${el.className || ''} ${el.getAttribute && el.getAttribute('role') || ''}`.toLowerCase();
             const style = getComputedStyle(el);
             const r = el.getBoundingClientRect ? el.getBoundingClientRect() : {width:0,height:0};
             return /(ad\b|ads\b|advert|popup|popunder|interstitial|overlay-ad|clickunder|modal|offer|subscribe|otp|verification)/i.test(text) ||
               (style.position === 'fixed' && r.width >= innerWidth * 0.55 && r.height >= innerHeight * 0.25);
           } catch (_) { return false; }
         };
         const neutralize = (el) => {
           el.setAttribute('data-sports-player-blocked-ad','1');
           el.style.setProperty('display','none','important');
           el.style.setProperty('pointer-events','none','important');
         };
         const hideUnsafePrompts = () => {
           try {
             document.querySelectorAll('form,input,button,a,[role="dialog"],[class*="popup" i],[id*="popup" i],[class*="advert" i],[id*="advert" i]').forEach((el) => {
                if (humanChallenge(el) || (el.closest && humanChallenge(el.closest('form,[role="dialog"],body')))) return;
               // مؤكَّد بسكرين شوت فعلي من المستخدم: إعلان مقلَّد بشكل نافذة
               // نظام ("انتباه"/"انقر للمزيد للمتابعة") يُحقَن غالباً **داخل**
               // حاوية المشغّل نفسها (.jwplayer/.jw-wrapper) — playerLike()
               // كان يستثنيه بالكامل قبل ما يوصل فحص sensitivePrompt أصلاً
               // (الاستثناء موجود لحماية أزرار تحكّم حقيقية، لا إعلانات
               // مقحَمة بداخل نفس الحاوية). الحل: افحص محتوى نص العنصر (أو
               // أقرب حاوية تشبه نافذة/مربع حوار له) بغض النظر عن كونه داخل
               // مشغّل أو لا — قائمة الكلمات محدَّدة بدقة كافية (لن تطابق
               // أزرار تحكّم حقيقية)، وتبقى محمية بحارس humanChallenge أعلاه
               // لأي كابتشا حقيقي. عنصر adLike() العام (حجم/موضع فقط، بلا
               // كلمة مفتاحية) يبقى مستثنى من داخل المشغّل كما كان — خطر
               // إيجابيات كاذبة أعلى (قائمة جودة حقيقية مثلاً).
               const dialogContainer = (el.closest &&
                 el.closest('[role="dialog"],[class*="modal" i],[class*="dialog" i],[class*="alert" i]')) || el;
               if (sensitivePrompt(el) || sensitivePrompt(dialogContainer)) {
                 neutralize(dialogContainer);
                 return;
               }
               if (playerLike(el)) return;
               if (adLike(el)) neutralize(el);
             });
             // طبقة ثانية ديناميكية بدون أي كلمة مفتاحية أو اسم كلاس: أي عنصر
             // مُلحَق مباشرة بـ<body> (نمط شبه ثابت لتراكبات الإعلانات
             // المزيّفة أياً كان اسم كلاسها/لغتها) يغطي مساحة كبيرة وثابتة من
             // الشاشة — تكتشفه adLike() فعلاً بفحص الحجم/الموضع، لكنها ما
             // كانت تُستدعى إلا على العناصر المحصورة بالسطر أعلاه. هذا يسد
             // الثغرة لأي تصميم إعلان جديد مستقبلاً دون تدخل يدوي.
             if (document.body) {
               Array.from(document.body.children).forEach((el) => {
                 if (el.hasAttribute && el.hasAttribute('data-sports-player-blocked-ad')) return;
                 if (playerLike(el)) return;
                 // playerLike() فقط يفحص الأسلاف (closest) — عنصر غلاف كامل
                 // الشاشة (position:fixed) قد يحتوي المشغّل الحقيقي كسليل
                 // بدل ما يكون هو نفسه المشغّل (تصميم شائع لمواقع مخصّصة
                 // للفيديو). لازم نفحص أيضاً وجود مشغّل بداخله قبل إخفائه —
                 // نفس نمط الفحص المزدوج (نفسه + أسلافه) المستخدَم أصلاً
                 // بـhumanChallenge().
                 if (el.querySelector && el.querySelector('video, audio, iframe, .video-js, .jwplayer, .jw-wrapper, .plyr, [class*="player" i], [id*="player" i]')) return;
                 if (humanChallenge(el)) return;
                 if (adLike(el)) neutralize(el);
               });
             }
           } catch (_) {}
         };
        const report = (payload) => {
          try {
            if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
              window.SportsPlayerSource.postMessage(JSON.stringify(payload));
            }
          } catch (_) {}
        };
        const manifestText = (text) => /#EXTM3U|#EXT-X-(STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE)/i.test(String(text || '').slice(0, 12000));
        const reportManifest = (url, source, mime) => {
          if (!url || !/^https?:\/\//i.test(String(url))) return;
          report({
            type:'hls_candidate',
            url:String(url),
            source:source || 'manifest-response',
            mime:mime || 'application/vnd.apple.mpegurl',
            pageUrl:location.href,
            frameUrl:location.href,
            referer:document.referrer || location.href
          });
        };
        const addCandidate = (value, source='network', mime='') => {
          try {
            if (!value || typeof value !== 'string') return;
            const v = value.trim();
            if (!/^https?:\/\//i.test(v)) return;
            window.__sportsPlayerMediaCandidates = window.__sportsPlayerMediaCandidates || [];
            if (window.__sportsPlayerMediaCandidates.indexOf(v) === -1) {
              window.__sportsPlayerMediaCandidates.push(v);
            }
            if (/\.(m3u8|m3u)(?:$|[?#])/i.test(v) ||
                /(?:master|playlist|manifest|hls)(?:[.?&=\/]|$)/i.test(v)) {
              report({
                type:'hls_candidate',
                url:v,
                source,
                mime,
                pageUrl:location.href,
                frameUrl:location.href,
                referer:document.referrer || location.href
              });
            }
          } catch (_) {}
        };
         const reportPayloadCandidates = (value, source='response-json', depth=0) => {
           try {
             if (depth > 6 || value == null) return;
             if (typeof value === 'string') {
               const text = value.trim();
               if (/^https?:\/\//i.test(text)) {
                 addCandidate(text, source);
               } else if (/(m3u8|master|playlist|manifest|hls)/i.test(text)) {
                 try { addCandidate(new URL(text, location.href).toString(), source); } catch (_) {}
               }
               return;
             }
             if (Array.isArray(value)) {
               value.slice(0, 40).forEach((item) => reportPayloadCandidates(item, source, depth + 1));
               return;
             }
             if (typeof value === 'object') {
               Object.keys(value).slice(0, 80).forEach((key) => {
                 const item = value[key];
                 if (/^(url|src|source|file|stream|streamUrl|playUrl|hls|dash|mpd|m3u8|manifest|playlist|media|sources)$/i.test(key) ||
                     depth < 2) {
                   reportPayloadCandidates(item, source, depth + 1);
                 }
               });
             }
           } catch (_) {}
         };
        window.open = function(url) {
          if (!url || blocked(url)) return null;
          // Never let a page-created secondary window steal the playback session.
          return null;
        };
        // Some ad-laden pages spam a native "Allow notifications?" prompt on
        // load or on first tap purely to farm push-subscriptions for later
        // spam/ad campaigns — it has nothing to do with playing the channel.
        // Answer it silently as denied instead of letting it interrupt the
        // viewer or, on some WebView builds, open a system permission sheet.
        try {
          if (window.Notification) {
            const deniedPromise = () => Promise.resolve('denied');
            try {
              Object.defineProperty(Notification, 'permission', { get: () => 'denied', configurable: true });
            } catch (_) {}
            Notification.requestPermission = function(cb) {
              if (typeof cb === 'function') { try { cb('denied'); } catch (_) {} }
              return deniedPromise();
            };
            const NoopNotification = function() { /* swallow: never actually shown */ };
            NoopNotification.permission = 'denied';
            NoopNotification.requestPermission = Notification.requestPermission;
            window.Notification = NoopNotification;
          }
        } catch (_) {}
        const markUserInteraction = (el) => {
          try {
            const r = el && el.getBoundingClientRect ? el.getBoundingClientRect() : null;
            window.__sportsPlayerLastClick = {
              at: Date.now(),
              x: r ? r.left + r.width / 2 : 0,
              y: r ? r.top + r.height / 2 : 0,
              text: ((el && (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title'))) || '').slice(0,120)
            };
          } catch (_) {}
        };
         document.addEventListener('click', (e) => {
          let el = e.target;
          if (el && el.nodeType === 3) el = el.parentElement;
          markUserInteraction(el);
          let link = el;
          while (link && link.tagName !== 'A') link = link.parentElement;
           const href = link ? link.getAttribute('href') || '' : '';
           const target = link ? (link.getAttribute('target') || '').toLowerCase() : '';
           if ((link && (target === '_blank' || target === '_new' || blocked(href))) ||
               (el && !playerLike(el) && (sensitivePrompt(el) || adLike(el)))) {
            e.preventDefault(); e.stopPropagation();
             if (e.stopImmediatePropagation) e.stopImmediatePropagation();
          }
        }, true);
         document.addEventListener('touchstart', (e) => {
           let el = e.target;
           if (el && el.nodeType === 3) el = el.parentElement;
           if (el && !playerLike(el) && (sensitivePrompt(el) || adLike(el))) {
             e.preventDefault(); e.stopPropagation();
             if (e.stopImmediatePropagation) e.stopImmediatePropagation();
           }
         }, {capture:true, passive:false});
        const style = document.createElement('style');
        style.id = 'sports-player-ad-cleanup';
          style.textContent = `[id*=\"popup\" i],[class*=\"popup\" i],[id*=\"popunder\" i],[class*=\"popunder\" i],[id*=\"advert\" i],[class*=\"advert\" i],[id*=\"adsbox\" i],[class*=\"adsbox\" i],[class*=\"overlay-ad\" i],[class*=\"interstitial\" i],[id*=\"otp\" i],[class*=\"otp\" i],[id*=\"verification\" i],[class*=\"verification\" i],[id*=\"subscribe\" i],[class*=\"subscribe\" i]{display:none!important;visibility:hidden!important;pointer-events:none!important;} iframe[src*=\"challenges.cloudflare.com\" i],iframe[src*=\"hcaptcha.com\" i],iframe[src*=\"recaptcha\" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha{display:block!important;visibility:visible!important;pointer-events:auto!important;}`;
        (document.head || document.documentElement).appendChild(style);
         hideUnsafePrompts();
         spObserve(new MutationObserver(() => hideUnsafePrompts()), document.documentElement || document, {subtree:true, childList:true, attributes:true, attributeFilter:['class','id','href','action','placeholder','name']});

        // Universal player intelligence: iframe URLs can appear/change only after Play.
        const iframeKey = (f) => { try { return `${f.src || ''}|${f.id || ''}|${f.className || ''}`; } catch (_) { return ''; } };
        const iframeSeen = new Set();
        const inspectIframes = () => {
          try {
            document.querySelectorAll('iframe').forEach((f) => {
              const src = (f.src || f.getAttribute('src') || '').trim();
              if (!/^https?:\/\//i.test(src)) return;
              const r = f.getBoundingClientRect();
              const st = getComputedStyle(f);
              if (r.width < 180 || r.height < 100 || st.display === 'none' || st.visibility === 'hidden') return;
              const text = `${src} ${f.id || ''} ${f.className || ''}`.toLowerCase();
            if (/(doubleclick|googlesyndication|adservice|adnxs|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|exoclick|juicyads|trafficjunky|adsterra|popup|popunder|clickunder|interstitial)/i.test(text)) {
              // معروف كإعلان — كان يُتجاهَل فقط من ترشيح المشغّل بدون تحييده
              // فعلياً، فيبقى ظاهراً تفاعلياً (يقدر يعرض أي محتوى بما فيه
              // تراكب كابتشا مزيّف). حيّده فعلياً بدل تجاهله فقط.
              try { f.style.setProperty('display','none','important'); f.style.setProperty('pointer-events','none','important'); } catch (_) {}
              return;
            }
              let score = 10;
              if (r.width >= 320 && r.height >= 180) score += 25;
              else if (r.width >= 250 && r.height >= 140) score += 15;
              if (r.bottom >= 0 && r.top <= innerHeight) score += 15;
              if (/(embed|shell|player|video|watch|stream|play|live)/i.test(text)) score += 30;
              if (/(player|video|stream|embed)/i.test(`${f.id || ''} ${f.className || ''}`)) score += 20;
              try { if (new URL(src, location.href).hostname !== location.hostname) score += 10; } catch (_) {}
              const key = iframeKey(f);
              if (!key || iframeSeen.has(key)) return;
              iframeSeen.add(key);
              report({type:'iframe_candidate', url:src, score, width:Math.round(r.width), height:Math.round(r.height)});
            });
          } catch (_) {}
        };
        inspectIframes();
        spObserve(new MutationObserver(() => inspectIframes()), document.documentElement || document, {subtree:true, childList:true, attributes:true, attributeFilter:['src','id','class','style']});
        spInterval(inspectIframes, 1200);

        const mediaResourceSeen = new Set();
        // مؤكَّد بسجل تشخيص فعلي (موقع مليء بإعلانات/تتبّع): إيجابيات كاذبة
        // حقيقيتان بهذا الفحص كانتا تخدعان النظام بالكامل ليعتقد أن تشغيلاً
        // حقيقياً أثبت نفسه خلال ثوانٍ من فتح الصفحة، رغم عدم وجود أي فيديو
        // بعد: (أ) روابط favicon من جوجل (`s2.googleusercontent.com/s2/
        // favicons?domain_url=...`) تضمّن رابط الصفحة نفسها بمعامل الاستعلام
        // — لصفحة مسلسل/حلقة هذا يحتوي غالباً كلمات "video"/"watch" فيُطابق
        // فحص الكلمات المفتاحية رغم إنه مجرد طلب أيقونة صغيرة. (ب) روابط
        // إعلانات كازينو حقيقية (`.../content/stream/agl/....gif`) تحتوي
        // كلمة "stream" بمسارها التسويقي (لا علاقة له بالبث)، فتُطابَق أيضاً.
        // النتيجة الفعلية المرصودة: _webMediaEvidenceScore وصل 100 خلال أقل
        // من 10 ثوانٍ من مجرد تحميل أيقونات وإعلانات، قبل حتى محاولة اكتشاف
        // أي مشغّل حقيقي — وهذا "الدليل" الكاذب يُسكِت آلية النقر التلقائي
        // (`_webInteractionAttempts` بـwatch_screen_discovery.dart، الشرط
        // `!await _webPlaybackSentinel(...)`) طوال الجلسة، فلا يُنقَر أي زر
        // سيرفر تلقائياً إطلاقاً على مواقع بهذا الشكل. الحل: (أ) فحص الكلمات
        // المفتاحية يتجاهل معامل الاستعلام كلياً الآن (نطاق+مسار فقط، لا
        // `search`) — رابط favicon يحمل الصفحة كاملة بمعامل استعلام لا يعود
        // يُطابَق. (ب) أي مورد نوعه الحقيقي (`initiatorType`) صورة/ستايل/خط
        // (`img`/`css`/`link`) أو امتداده صورة/خط معروف يُستبعَد قبل أي فحص
        // كلمات مفتاحية إطلاقاً — شريحة/قائمة تشغيل حقيقية لا تُحمَّل أبداً
        // بهذي الأنواع.
        const mediaResourceLike = (url, initiatorType) => {
          try {
            if (/^(img|css|link)$/i.test(initiatorType || '')) return false;
            const u = new URL(url, location.href);
            const pathOnly = `${u.hostname} ${u.pathname}`.toLowerCase();
            if (/\.(jpe?g|png|gif|webp|bmp|svg|ico|woff2?|ttf|eot|otf)(?:$|[?#])/i.test(pathOnly)) return false;
            if (/(doubleclick|googlesyndication|google-analytics|mc\.yandex|scorecardresearch|adservice|ads\b|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|beacon|telemetry|metrics|pixel|collect|favicon)/i.test(pathOnly)) return false;
            return /\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/i.test(pathOnly) ||
              /(?:manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/|\/m3\/)/i.test(pathOnly);
          } catch (_) { return false; }
        };
        const reportMediaResources = () => {
          try {
            performance.getEntriesByType('resource').forEach((e) => {
              const name = e && e.name ? String(e.name) : '';
              if (!mediaResourceLike(name, e && e.initiatorType)) return;
              report({type:'media_resource', url:name});
              if (/\.(m3u8|m3u)(?:$|[?#])/i.test(name) ||
                  /(?:master|playlist|manifest)(?:[./?#&]|$)|\/m3\//i.test(name)) {
                report({type:'hls_candidate', url:name, source:'performance',
                  mime:e.initiatorType || '', pageUrl:location.href,
                  frameUrl:location.href, referer:document.referrer || location.href});
              }
            });
          } catch (_) {}
        };
        reportMediaResources();
        spInterval(reportMediaResources, 1800);

        // Video.js intelligence: some hosts expose the master only after the
        // player instance is created or after Play. Inspect the public player
        // API and registry repeatedly instead of trusting one DOM selector.
        try {
           const addVideoJsSource = (value, source='videojs') => {
             try {
               if (!value) return;
               if (typeof value === 'object') {
                 if (typeof value.src === 'function') addVideoJsSource(value.src(), source);
                 if (typeof value.currentSrc === 'function') addVideoJsSource(value.currentSrc(), source);
                 if (typeof value.currentSource === 'function') addVideoJsSource(value.currentSource(), source);
                 if (typeof value.currentSources === 'function') addVideoJsSource(value.currentSources(), source);
                 if (Array.isArray(value)) { value.slice(0,40).forEach(v => addVideoJsSource(v, source)); return; }
                 Object.keys(value).slice(0,80).forEach(k => {
                   if (/^(src|source|sources|url|file|playlist|hls|m3u8|manifest)$/i.test(k)) addVideoJsSource(value[k], source);
                 });
                 return;
               }
               const v = String(value).trim();
               if (!/^https?:\/\//i.test(v)) return;
               addCandidate(v, source);
               if (/\.(m3u8|m3u)(?:$|[?#])/i.test(v) || /(?:master|playlist|manifest|hls)(?:[?&=\/]|$)/i.test(v)) {
                 report({type:'hls_candidate', url:v, source, mime:'application/vnd.apple.mpegurl'});
               }
             } catch (_) {}
           };
           const inspectVideoJsPlayers = () => {
             try {
               const players = [];
               if (window.videojs) {
                 if (typeof window.videojs.getPlayers === 'function') players.push(...Object.values(window.videojs.getPlayers() || {}));
                 if (typeof window.videojs.getAllPlayers === 'function') players.push(...(window.videojs.getAllPlayers() || []));
                 document.querySelectorAll('.video-js,[data-setup],video[id]').forEach((el) => {
                   try {
                     const p = window.videojs.getPlayer ? window.videojs.getPlayer(el.id || el) : window.videojs(el.id || el);
                     if (p) players.push(p);
                   } catch (_) {}
                 });
               }
               players.forEach((p) => {
                 addVideoJsSource(p, 'videojs-api');
                 try { if (typeof p.tech === 'function') addVideoJsSource(p.tech(true), 'videojs-tech'); } catch (_) {}
               });
             } catch (_) {}
           };
          const detectVideoJs = () => {
            try {
              const text = `${document.documentElement?.innerHTML || ''} ${Array.from(document.scripts || []).map(s => s.src || s.textContent || '').join(' ')}`;
               const hasVideoJs = !!window.videojs || !!document.querySelector('.video-js,[data-setup]') ||
                 /video-js|videojs|video\.min\.js|videojs-contrib-quality-levels|videojs-hls-quality-selector/i.test(text);
               const hasVideo = !!document.querySelector('video,.video-js,[data-setup]');
               if (hasVideoJs && hasVideo) {
                 inspectVideoJsPlayers();
                 report({type:'videojs_player', initialized:!!window.videojs, hasVideo:true});
               }
            } catch (_) {}
          };
          detectVideoJs();
           spInterval(detectVideoJs, 900);
        } catch (_) {}

        // JWPlayer intelligence: same idea as the Video.js block above, but
        // detected by feature (window.jwplayer / jw-* markup) instead of by
        // domain, so any site running JWPlayer gets the same treatment —
        // not just the small list of hosts _isVidmolyPlayerUrl knows about.
        try {
          const detectJwPlayer = () => {
            try {
              const text = `${document.documentElement?.innerHTML || ''} ${Array.from(document.scripts || []).map(s => s.src || s.textContent || '').join(' ')}`;
              const hasJwPlayer = !!window.jwplayer || !!document.querySelector('.jwplayer,.jw-wrapper,.jw-video,[id*="jwplayer" i],[class*="jwplayer" i]') ||
                /jwplayer|jwplatform|jwpsrv/i.test(text);
              const hasVideo = !!document.querySelector('video,.jwplayer,.jw-wrapper');
              if (hasJwPlayer && hasVideo) {
                report({type:'jwplayer_player', initialized:!!window.jwplayer, hasVideo:true});
              }
            } catch (_) {}
          };
          detectJwPlayer();
          spInterval(detectJwPlayer, 900);
        } catch (_) {}

        // Playback heartbeat: a large class of embedded players use MSE,
        // MediaSource blobs, canvas overlays, or framework wrappers where
        // URL-based discovery is insufficient. Observe the real HTML5 media
        // element and report it as soon as the browser has actually started
        // playback. This also catches playback that began from a genuine user
        // tap before our next polling cycle.
        const playbackSeen = new WeakSet();
        const inspectPlayback = () => {
          try {
            document.querySelectorAll('video,audio').forEach((v) => {
              if (!v) return;
              const reportState = () => {
                try {
                  const ready = v.readyState >= 2;
                  const playing = !v.paused && !v.ended && ready;
                  const time = Number(v.currentTime || 0);
                   addCandidate(v.currentSrc || v.src || '', 'video-event');
                   if (window.videojs) {
                     try {
                       const p = v.id && window.videojs.getPlayer ? window.videojs.getPlayer(v.id) : null;
                       if (p) {
                         if (typeof p.currentSrc === 'function') addCandidate(p.currentSrc(), 'videojs-currentSrc');
                         if (typeof p.src === 'function') {
                           const source = p.src();
                           if (typeof source === 'string') addCandidate(source, 'videojs-src');
                           else if (Array.isArray(source)) source.forEach(item => {
                             if (item && typeof item.src === 'string') addCandidate(item.src, 'videojs-src');
                           });
                         }
                       }
                     } catch (_) {}
                   }
                  if (playing || ready || time > 0.15) {
                    report({type:'web_playback', playing, ready, time, src:(v.currentSrc || v.src || '')});
                  }
                } catch (_) {}
              };
              if (!playbackSeen.has(v)) {
                playbackSeen.add(v);
                   ['play','playing','timeupdate','canplay','loadedmetadata','loadeddata','durationchange'].forEach((name) => {
                  try { v.addEventListener(name, reportState, {passive:true}); } catch (_) {}
                });
              }
              reportState();
            });
          } catch (_) {}
        };
        inspectPlayback();
        spInterval(inspectPlayback, 450);

        try {
          const originalRequestMediaKeySystemAccess = navigator.requestMediaKeySystemAccess;
          if (typeof originalRequestMediaKeySystemAccess === 'function' && !navigator.__sportsPlayerEmeHooked) {
            navigator.__sportsPlayerEmeHooked = true;
            navigator.requestMediaKeySystemAccess = function(keySystem, supportedConfigurations) {
              report({type:'drm_detected', system:String(keySystem || 'unknown')});
              return originalRequestMediaKeySystemAccess.apply(this, arguments);
            };
          }
        } catch (_) {}

        try {
          if (window.fetch && !window.__sportsPlayerFetchHooked) {
            window.__sportsPlayerFetchHooked = true;
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
              try { addCandidate(typeof input === 'string' ? input : (input && input.url), 'fetch'); } catch (_) {}
              return originalFetch.apply(this, arguments).then((response) => {
                try { addCandidate(response && response.url, 'fetch-response'); } catch (_) {}
                const responseUrl = response && response.url ? response.url : (typeof input === 'string' ? input : '');
                const responseMime = response && response.headers ? (response.headers.get('content-type') || '') : '';
                if (/mpegurl/i.test(responseMime)) {
                  reportManifest(responseUrl, 'fetch-content-type', responseMime);
                }
                 try {
                   const copy = response.clone();
                   copy.text().then((text) => {
                     if (!text) return;
                     if (manifestText(text)) {
                       reportManifest(responseUrl, 'fetch-manifest', responseMime);
                     } else {
                       try { reportPayloadCandidates(JSON.parse(text), 'fetch-json'); } catch (_) {}
                     }
                   }).catch(() => {});
                 } catch (_) {}
                return response;
              });
            };
          }
        } catch (_) {}
        try {
          if (window.XMLHttpRequest && !window.__sportsPlayerXhrHooked) {
            window.__sportsPlayerXhrHooked = true;
            const OriginalXHR = window.XMLHttpRequest;
            const originalOpen = OriginalXHR.prototype.open;
            OriginalXHR.prototype.open = function(method, url) {
               const result = originalOpen.apply(this, arguments);
               try {
                 addCandidate(url, 'xhr');
                 this.addEventListener('load', () => {
                   try {
                     const responseUrl = this.responseURL || url || '';
                     const responseMime = this.getResponseHeader('content-type') || '';
                     if (typeof this.responseText === 'string' && this.responseText) {
                       if (manifestText(this.responseText)) {
                         reportManifest(responseUrl, 'xhr-manifest', responseMime);
                       } else {
                         reportPayloadCandidates(JSON.parse(this.responseText), 'xhr-json');
                       }
                       return;
                     }
                     // بعض مواقع الأفلام تطلب responseType=arraybuffer/blob عمداً
                     // حتى لا يستطيع أي فاحص بسيط قراءة this.responseText مباشرة.
                     // نفك ترميز البايتات هنا كنص UTF-8 ونطبّق نفس فحص #EXTM3U.
                     if (this.response instanceof ArrayBuffer) {
                       const text = new TextDecoder('utf-8').decode(this.response);
                       if (manifestText(text)) {
                         reportManifest(responseUrl, 'xhr-manifest-buffer', responseMime);
                       }
                     } else if (this.response instanceof Blob) {
                       this.response.text().then((text) => {
                         if (manifestText(text)) {
                           reportManifest(responseUrl, 'xhr-manifest-blob', responseMime);
                         }
                       }).catch(() => {});
                     }
                   } catch (_) {}
                 });
               } catch (_) {}
               return result;
            };
          }
        } catch (_) {}
      } catch (_) {}
    })();''';

/// استخراج روابط الوسائط العامة التي تعرضها الصفحة نفسها.
const String kDetectPublicMediaSourcesScript = r"""(() => {
        const out = new Set();
        const add = (value) => {
          if (!value || typeof value !== 'string') return;
          const v = value.trim();
          if (!/^https?:\/\//i.test(v)) return;
          const l = v.toLowerCase();
          if (/\.(m3u8|mpd|mp4|m4v|webm|mov)(?:$|[?#])/i.test(v) ||
              /(?:m3u8|manifest|playlist|master|stream|live|hls)(?:[.?&=\/]|$)/i.test(l) ||
              /\/m3\//i.test(l)) out.add(v);
        };
        document.querySelectorAll('video').forEach(v => {
          add(v.currentSrc); add(v.src);
          v.querySelectorAll('source').forEach(s => add(s.src));
        });
        document.querySelectorAll('source').forEach(s => add(s.src));
        document.querySelectorAll('iframe').forEach(f => add(f.src));
        try { performance.getEntriesByType('resource').forEach(e => add(e.name)); } catch (_) {}
        try {
          const html = document.documentElement ? document.documentElement.innerHTML : '';
          const urls = html.match(/https?:\/\/[^\s\"'<>]+/gi) || [];
          urls.forEach(add);
        } catch (_) {}
        try { (window.__sportsPlayerMediaCandidates || []).forEach(add); } catch (_) {}
        return JSON.stringify(Array.from(out));
      })();""";

/// التقاط سياق الصفحة (referer/origin/cookie/userAgent) لإعادة استخدامه
/// بطلبات التشغيل الأصلي.
const String kCaptureWebContextScript = r'''(() => {
        const videos = Array.from(document.querySelectorAll('video'));
        let best = null;
        for (const v of videos) {
          try {
            const r = v.getBoundingClientRect();
            const score = (r.width * r.height) + (v.readyState >= 2 ? 1000000 : 0) + (!v.paused ? 500000 : 0);
            if (!best || score > best.score) best = {v, score};
          } catch (_) {}
        }
        const v = best ? best.v : null;
        let seekable = false;
        if (v) { try { seekable = v.seekable && v.seekable.length > 0 && (v.seekable.end(v.seekable.length - 1) - v.seekable.start(0)) > 1; } catch (_) {} }
        const duration = v && Number.isFinite(v.duration) ? (v.duration || 0) : 0;
        let mediaHits = 0;
        let lastMedia = '';
        try {
          // نفس إصلاح mediaResourceLike أعلى بالملف (مسافة الأسماء JS
          // منفصلة هنا لأن هذا الحقن مستقل، لكن نفس فئة الإيجابية الكاذبة
          // بالضبط — راجع تعليقها لسبب استبعاد search/الصور): يتجاهل معامل
          // الاستعلام (رابط favicon يحمل صفحة الحلقة كاملة به) ويستبعد
          // موارد الصور/الأيقونات صراحة (initiatorType أو الامتداد).
          performance.getEntriesByType('resource').forEach((e) => {
            if (/^(img|css|link)$/i.test(e.initiatorType || '')) return;
            let pathOnly = '';
            try {
              const u = new URL(e.name || '', location.href);
              pathOnly = `${u.hostname} ${u.pathname}`.toLowerCase();
            } catch (_) { return; }
            if (/\.(jpe?g|png|gif|webp|bmp|svg|ico|woff2?|ttf|eot|otf)(?:$|[?#])/.test(pathOnly)) return;
            if (/(doubleclick|googlesyndication|google-analytics|mc\.yandex|adservice|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|beacon|telemetry|metrics|pixel|collect|favicon)/.test(pathOnly)) return;
            if (/\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/.test(pathOnly) || /(?:manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/|\/m3\/)/.test(pathOnly)) {
              mediaHits++; lastMedia = e.name;
            }
          });
        } catch (_) {}
        return JSON.stringify({found:!!v, playing:!!(v && !v.paused && v.readyState >= 2), time:Number(v && v.currentTime || 0), duration, seekable, src:v ? (v.currentSrc || v.src || '') : '', mediaHits, lastMedia});
      })();''';

/// تفاعل ذكي مع الصفحة (نقر زر تشغيل/سيرفر) لإجبار المشغّل على كشف
/// مصدره الحقيقي.
const String kSmartInteractionScript = r'''(() => {
        const normalize = (s) => (s || '').toString().trim().replace(/\s+/g, ' ').toLowerCase();
        const blockedText = /(login|sign[ -]?in|subscribe|subscription|purchase|buy|download|advert|ads|privacy|cookie|close|share|facebook|twitter|telegram|whatsapp|notification|allow)/i;
        const playText = /(play|watch|live|watch live|start|start stream|watch now|تشغيل|مشاهدة|بث مباشر|مشاهدة مباشرة|ابدأ|ابدأ البث|شاهد الآن)/i;
        const playerSelector = 'video,iframe,.jwplayer,.jw-wrapper,.video-js,.plyr,.shaka-video-container,[class*="player" i],[id*="player" i]';
        const enabled = (el) => !!el && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
        const labelOf = (el) => normalize([
          el.getAttribute('aria-label'), el.getAttribute('title'), el.innerText,
          el.textContent, el.getAttribute('data-testid'), el.id, el.className,
          el.getAttribute('data-action'), el.getAttribute('data-play')
        ].join(' '));

        // Layer 0: locate the real player even when it starts below the fold.
        let media = Array.from(document.querySelectorAll(playerSelector)).filter((el) => {
          if (!el || !el.isConnected) return false;
          const r = el.getBoundingClientRect();
          return r.width >= 160 && r.height >= 90;
        });
        media.sort((a,b) => {
          const ar=a.getBoundingClientRect(), br=b.getBoundingClientRect();
          return (br.width*br.height)-(ar.width*ar.height);
        });
        const player = media[0] || null;
        if (player) {
          try { player.scrollIntoView({block:'center', inline:'center', behavior:'instant'}); } catch (_) {}
        }

        // Layers 1/2: known player controls and text-labelled controls.
        const candidates = [];
        const seen = new Set();
        const selectors = 'button,[role="button"],a,[aria-label],[title],[onclick],[tabindex],input[type="button"],input[type="submit"],.jw-icon-play,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.ytp-large-play-button,[data-play],[data-action*="play" i],[class*="play-btn" i],[class*="playbtn" i],[id*="play-btn" i],[id*="playbtn" i]';
        const addCandidate = (el, base) => {
          if (!el || !el.isConnected || !enabled(el)) return;
          const label = labelOf(el);
          if (blockedText.test(label)) return;
          const r = el.getBoundingClientRect();
          if (r.width < 18 || r.height < 18) return;
          const st = getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return;
          if (r.right < 0 || r.bottom < 0 || r.left > innerWidth || r.top > innerHeight) return;
          let score = base || 0;
          if (playText.test(label)) score += 35;
          if (/play|player|video|watch|live/.test(label)) score += 20;
          if (el.matches && el.matches('.jw-icon-play,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.ytp-large-play-button,[data-play],[class*="play-btn" i],[class*="playbtn" i],[id*="play-btn" i],[id*="playbtn" i]')) score += 60;
          if (el.hasAttribute('aria-label')) score += 15;
          if (el.hasAttribute('title')) score += 10;
          if (player) {
            const pr = player.getBoundingClientRect();
            const cx=r.left+r.width/2, cy=r.top+r.height/2;
            const px=pr.left+pr.width/2, py=pr.top+pr.height/2;
            const d=Math.hypot(cx-px,cy-py);
            if (d < 120) score += 55;
            else if (d < 250) score += 25;
            if (cx >= pr.left-30 && cx <= pr.right+30 && cy >= pr.top-30 && cy <= pr.bottom+30) score += 35;
          }
          const adAncestor = el.closest('[id*="ad" i],[class*="ad" i],[id*="popup" i],[class*="popup" i],[id*="overlay-ad" i]');
          if (adAncestor) score -= 150;
          const key = `${el.tagName}|${label}|${Math.round(r.left)}|${Math.round(r.top)}`;
          if (!seen.has(key)) { seen.add(key); candidates.push({el,score,label}); }
        };
        document.querySelectorAll(selectors).forEach((el) => addCandidate(el, 0));
        candidates.sort((a,b) => b.score-a.score);
        const best = candidates[0];
        if (best && best.score >= 55) {
          try {
            best.el.scrollIntoView({block:'center', inline:'center', behavior:'instant'});
            best.el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,view:window}));
            best.el.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true,view:window}));
            best.el.click();
            return JSON.stringify({clicked:true, layer:1, score:best.score, label:best.label.slice(0,160)});
          } catch (_) {}
        }

        // Layer 3: geometric fallback around the player's center. This covers
        // custom icon-only buttons such as the yellow circular button in the
        // supplied screenshot, without clicking arbitrary page links.
        if (player) {
          const pr = player.getBoundingClientRect();
          const cx = pr.left + pr.width/2, cy = pr.top + pr.height/2;
          let el = document.elementFromPoint(cx, cy);
          const chain = [];
          for (let i=0; el && i<6; i++, el=el.parentElement) chain.push(el);
          for (const candidate of chain) {
            const label = labelOf(candidate);
            if (!enabled(candidate) || blockedText.test(label)) continue;
            if (candidate.tagName === 'A' && !playText.test(label)) continue;
            const r=candidate.getBoundingClientRect();
            if (r.width < 24 || r.height < 24 || r.width > pr.width*0.95 || r.height > pr.height*0.95) continue;
            const adAncestor = candidate.closest('[id*="ad" i],[class*="ad" i],[id*="popup" i],[class*="popup" i],[class*="overlay-ad" i]');
            if (adAncestor) continue;
            try {
              candidate.click();
              return JSON.stringify({clicked:true, layer:3, score:40, label:label.slice(0,160)});
            } catch (_) {}
          }
        }

        // Layer 4: HTML5 fallback. The browser still enforces its own gesture,
        // DRM and authentication rules; we do not bypass them.
        const v = document.querySelector('video');
        if (v && typeof v.play === 'function') {
          try {
            const p = v.play();
            if (p && typeof p.catch === 'function') p.catch(() => {});
            return JSON.stringify({clicked:true, layer:4, score:30, label:'video.play()'});
          } catch (_) {}
        }
        return JSON.stringify({clicked:false, reason:'no-safe-play-control'});
      })();''';

/// استخراج المصادر من إعدادات مشغّلات معروفة (JWPlayer/Video.js...).
const String kDetectFrameworkSourcesScript = r'''(() => {
        const out = new Set();
        const add = (value) => {
          if (!value || typeof value !== 'string') return;
          let v = value.trim();
          if (!v) return;
          try { v = new URL(v, location.href).toString(); } catch (_) { return; }
          if (/^https?:\/\//i.test(v)) out.add(v);
        };
        const nonMediaAsset = /\.(jpe?g|png|gif|webp|bmp|svg|ico|css|woff2?|ttf|eot|otf|json|swf|wasm)(?:$|[?#])/i;
        const addDeep = (value, depth=0) => {
          if (depth > 5 || value == null) return;
          if (typeof value === 'string') {
            const trimmed = value.trim();
            // "sources"/"file" objects also commonly carry a sibling "image"/
            // "poster" thumbnail field. A blanket "any https:// string" match
            // was sweeping those in too — they are never a playable source.
            if (nonMediaAsset.test(trimmed)) return;
            if (/^https?:\/\//i.test(trimmed) || /\.(m3u8|mpd|mp4|m4v|webm|mov)(?:$|[?#])/i.test(trimmed)) add(value);
            return;
          }
          if (Array.isArray(value)) { value.slice(0,40).forEach(v => addDeep(v, depth+1)); return; }
          if (typeof value === 'object') {
            Object.keys(value).slice(0,80).forEach(k => {
              const v = value[k];
              if (/^(file|src|source|url|uri|stream|streamUrl|playUrl|hls|dash|mpd|m3u8|playlist|media|sources)$/i.test(k)) addDeep(v, depth+1);
              else if (depth < 2) addDeep(v, depth+1);
            });
          }
        };
        document.querySelectorAll('video,audio').forEach(v => {
          add(v.currentSrc); add(v.src);
          v.querySelectorAll('source').forEach(s => add(s.src || s.getAttribute('src')));
        });
        try {
          if (window.jwplayer) {
            document.querySelectorAll('[id],[class]').forEach(el => {
              const id = el.id || '';
              const cls = typeof el.className === 'string' ? el.className : '';
              if (!/jwplayer|jw-video|jw-wrapper/i.test(id + ' ' + cls)) return;
              try {
                const p = window.jwplayer(id || el);
                if (p) {
                  try { addDeep(p.getPlaylist ? p.getPlaylist() : null); } catch (_) {}
                  try { addDeep(p.getConfig ? p.getConfig() : null); } catch (_) {}
                  try { addDeep(p.getPlaylistItem ? p.getPlaylistItem() : null); } catch (_) {}
                }
              } catch (_) {}
            });
          }
        } catch (_) {}
        try {
          if (window.videojs) {
             try {
               const registry = typeof window.videojs.getPlayers === 'function'
                 ? window.videojs.getPlayers()
                 : (typeof window.videojs.getAllPlayers === 'function' ? window.videojs.getAllPlayers() : null);
               const players = Array.isArray(registry) ? registry : Object.values(registry || {});
               players.forEach((p) => {
                 try {
                   if (typeof p.currentSrc === 'function') add(p.currentSrc());
                   if (typeof p.src === 'function') addDeep(p.src());
                   if (typeof p.currentSource === 'function') addDeep(p.currentSource());
                   if (typeof p.currentSources === 'function') addDeep(p.currentSources());
                   if (typeof p.tech === 'function') addDeep(p.tech(true));
                 } catch (_) {}
               });
             } catch (_) {}
            document.querySelectorAll('.video-js, video[id]').forEach(el => {
               try {
                 const p = window.videojs.getPlayer ? window.videojs.getPlayer(el.id || el) : window.videojs(el.id || el);
                 if (p) {
                   addDeep(p);
                   if (typeof p.currentSrc === 'function') add(p.currentSrc());
                   if (typeof p.src === 'function') addDeep(p.src());
                   if (typeof p.currentSource === 'function') addDeep(p.currentSource());
                 }
               } catch (_) {}
            });
          }
        } catch (_) {}
        try {
          if (window.player && typeof window.player === 'object') addDeep(window.player);
          if (window.__INITIAL_STATE__) addDeep(window.__INITIAL_STATE__);
          if (window.__NEXT_DATA__) addDeep(window.__NEXT_DATA__);
          if (window.__NUXT__) addDeep(window.__NUXT__);
        } catch (_) {}
        try {
          document.querySelectorAll('[data-src],[data-url],[data-file],[data-stream],[data-playlist],[data-config],[data-source]').forEach(el => {
            ['data-src','data-url','data-file','data-stream','data-playlist','data-config','data-source'].forEach(a => addDeep(el.getAttribute(a)));
          });
          document.querySelectorAll('script').forEach(script => {
            const text = script.textContent || '';
            if (/jwplayer|videojs|playlist|m3u8|\.mpd|\.mp4|streamUrl|playUrl/i.test(text)) {
              (text.match(/https?:\/\/[^\s"'<>]+/gi) || []).forEach(add);
              (text.match(/['"]([^'"]+\.(?:m3u8|mpd|mp4|m4v|webm|mov)(?:\?[^'"]*)?)['"]/gi) || []).forEach(x => add(x.replace(/^['"]|['"]$/g,'')));
            }
          });
        } catch (_) {}
        return JSON.stringify(Array.from(out));
      })();''';

/// تثبيت التركيز على عنصر المشغّل الحقيقي داخل الصفحة.
const String kPlayerFocusScript = r'''(() => {
        const visible = (el) => {
          if (!el) return false;
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width >= 160 && r.height >= 90 && s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0';
        };
        const candidates = Array.from(document.querySelectorAll('video,iframe,.jwplayer,.jw-wrapper,.video-js,.plyr,.shaka-video-container'))
          .filter(visible);
        if (!candidates.length) return JSON.stringify({ok:false});
        const media = candidates.sort((a,b) => {
          const ar=a.getBoundingClientRect(), br=b.getBoundingClientRect();
          return (br.width*br.height)-(ar.width*ar.height);
        })[0];
        let root = media;
        const mediaRect = media.getBoundingClientRect();
        for (let i=0;i<4 && root.parentElement;i++) {
          const p=root.parentElement;
          const r=p.getBoundingClientRect();
          if (r.width >= mediaRect.width*0.9 && r.height >= mediaRect.height*0.9) root=p;
          else break;
        }
        document.querySelectorAll('*').forEach(el => {
          el.setAttribute('data-sports-player-focus-hidden','1');
          el.style.setProperty('visibility','hidden','important');
        });
        const reveal = (el) => {
          if (!el) return;
          el.style.setProperty('visibility','visible','important');
        };
        reveal(document.documentElement);
        reveal(document.body);
        let n=root;
        while(n){ reveal(n); n=n.parentElement; }
        root.querySelectorAll('*').forEach(reveal);
        root.style.setProperty('max-width','100vw','important');
        root.style.setProperty('box-sizing','border-box','important');
        try { root.scrollIntoView({block:'center', inline:'center', behavior:'instant'}); } catch (_) {}
        return JSON.stringify({ok:true});
      })();''';

/// تهيئة تشغيل Video.js/HTML5 بعد كشفه.
const String kVideoJsPrimeScript = r"""(() => {
        try {
          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 20 && r.height > 20 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
          };
          const scoreButton = (el) => {
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
            const idcls = `${el.id || ''} ${el.className || ''}`;
            if (/login|subscribe|purchase|buy|download|advert|close/i.test(`${text} ${idcls}`)) return -100;
            let score = 0;
            if (/^(play|start|watch|live|تشغيل|ابدأ|شاهد|مشاهدة|بدء)$/i.test(text)) score += 80;
            if (/(vjs-big-play-button|play-control|play|start|watch|live)/i.test(idcls)) score += 35;
            return score;
          };
          let best = null, bestScore = 0;
          document.querySelectorAll('button,[role=\"button\"],a,[class*=\"play\" i],[id*=\"play\" i]').forEach(el => {
            if (!visible(el)) return;
            const s = scoreButton(el);
            if (s > bestScore) { best = el; bestScore = s; }
          });
          if (best) {
            try { best.scrollIntoView({block:'center',inline:'center'}); } catch (_) {}
            try { best.click(); } catch (_) {}
          }
          if (window.videojs) {
            document.querySelectorAll('video').forEach(v => {
              try {
                const player = v.id ? window.videojs.getPlayer(v.id) : null;
                if (player && typeof player.play === 'function') player.play();
              } catch (_) {}
            });
          }
          document.querySelectorAll('video,audio').forEach(v => {
            try { if (v.paused && v.readyState >= 2) v.play().catch(() => {}); } catch (_) {}
          });
        } catch (_) {}
      })();""";

/// تهيئة تشغيل JWPlayer/vidmoly بعد كشفه.
const String kVidmolyPrimeScript = r"""(() => {
        try {
          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 20 && r.height > 20 && cs.display !== 'none' && cs.visibility !== 'hidden';
          };
          const nodes = Array.from(document.querySelectorAll('button,[role=\"button\"],a,[class*=\"play\" i],[id*=\"play\" i]'));
          for (const el of nodes) {
            if (!visible(el)) continue;
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
            const idcls = `${el.id || ''} ${el.className || ''}`;
            if (/^(play|start|watch|live|تشغيل|ابدأ|شاهد|مشاهدة|بدء)$/i.test(text) || /(^|\W)(play|start|watch|jw-icon-play|jwplayer)(\W|$)/i.test(idcls)) {
              try { el.scrollIntoView({block:'center', inline:'center'}); } catch (_) {}
              try { el.click(); } catch (_) {}
              break;
            }
          }
          if (window.jwplayer) {
            const roots = document.querySelectorAll('[id],[class]');
            for (const el of roots) {
              const id = el.id || '';
              const cls = typeof el.className === 'string' ? el.className : '';
              if (!/jwplayer|jw-wrapper|jw-video/i.test(`${id} ${cls}`)) continue;
              try {
                const p = window.jwplayer(id || el);
                if (p && typeof p.play === 'function') { p.play(); break; }
              } catch (_) {}
            }
          }
          document.querySelectorAll('video').forEach(v => {
            try { if (v.paused && v.readyState >= 2) v.play().catch(() => {}); } catch (_) {}
          });
        } catch (_) {}
      })();""";

/// كاسح التراكبات الإعلانية — **بنيوي لا لغوي**.
///
/// قوائم الكلمات المفتاحية (روبوت/انتباه/verify...) تُهزم بتغيير نص واحد،
/// وأسماء الكلاسات تُولَّد عشوائياً أصلاً لتفادي الفلاتر. هذا الكاسح لا
/// يقرأ أي كلمة ولا يعتمد أي اسم: يحكم بالسلوك والشكل الهندسي فقط، فيبقى
/// صالحاً مهما تغيّر شكل الإعلان أو مضمونه أو لغته.
///
/// **بوابة إلزامية** (شرط لا يكفي غيره): إما أن يحوي العنصر رابطاً/زراً
/// لنطاق مختلف أو يفتح نافذة جديدة (هدف الإعلان الوحيد أصلاً)، أو أن يكون
/// خارج حاوية المشغّل رغم تغطيته للفيديو. هذا تحديداً ما يمنع حجب واجهة
/// مشغّل حقيقية بالخطأ: قائمة جودة حقيقية تظهر بعد التشغيل وبمنتصف
/// الفيديو، لكنها داخل حاوية المشغّل وبلا أي رابط خارجي.
///
/// وأي تحدٍّ بشري حقيقي (Cloudflare/hCaptcha/reCAPTCHA) مستثنى صراحةً
/// ليبقى ظاهراً وقابلاً للحل — الحجب هنا للإعلانات المزيّفة فقط.
const String kOverlayAdSweeperScript = r'''(() => {
  try {
    if (window.__sportsPlayerOverlaySweeper) return;
    window.__sportsPlayerOverlaySweeper = true;

    const REAL_CHALLENGE = 'iframe[src*="challenges.cloudflare.com" i],iframe[src*="hcaptcha.com" i],iframe[src*="recaptcha" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha';
    const PLAYER_BOX = 'video,.video-js,.jwplayer,.jw-wrapper,.plyr,[class*="player" i],[id*="player" i]';

    const report = (payload) => {
      try {
        if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
          window.SportsPlayerSource.postMessage(JSON.stringify(payload));
        }
      } catch (_) {}
    };

    const bornAt = new WeakMap();
    let playbackStartedAt = 0;

    const notePlayback = () => {
      if (playbackStartedAt) return;
      try {
        document.querySelectorAll('video,audio').forEach((v) => {
          if (!v.paused && v.currentTime > 0.2) playbackStartedAt = Date.now();
        });
      } catch (_) {}
    };

    // **ثغرة مؤكَّدة من لقطتَي شاشة أرسلهما المستخدم**: كان الكاسح يرجع 0
    // لكل عنصر حين لا يجد عنصر <video> بحجم معقول — وهذا بالضبط حال
    // اللقطة الأولى: الإعلان المقلَّد ظهر فوق **صورة الغلاف قبل بدء
    // التشغيل**، حيث لم يكن JWPlayer قد أنشأ عنصر <video> بعد (أو أنشأه
    // بحجم صفري). فكان الكاسح أعمى تماماً باللحظة التي يظهر فيها الإعلان
    // فعلياً.
    //
    // البديل حين لا يوجد <video> صالح: حاوية المشغّل نفسها، وإلا فالنافذة
    // كاملةً — نحن داخل مستند تضمين لا يحوي شيئاً غير المشغّل أصلاً، فأي
    // تراكب يغطّي وسطه هو المقصود بالضبط. البوابة الإلزامية (رابط خارجي أو
    // خارج حاوية المشغّل) تبقى كما هي، فلا تتوسّع دائرة الحجب.
    const videoRects = () => {
      const rects = [];
      try {
        document.querySelectorAll('video').forEach((v) => {
          const r = v.getBoundingClientRect();
          if (r.width >= 80 && r.height >= 60) rects.push(r);
        });
      } catch (_) {}
      if (rects.length) return rects;
      try {
        document.querySelectorAll(PLAYER_BOX).forEach((box) => {
          const r = box.getBoundingClientRect();
          if (r.width >= 200 && r.height >= 120) rects.push(r);
        });
      } catch (_) {}
      if (rects.length) return rects;
      try {
        const w = window.innerWidth || 0;
        const h = window.innerHeight || 0;
        if (w >= 200 && h >= 120) {
          rects.push({left: 0, top: 0, right: w, bottom: h, width: w, height: h});
        }
      } catch (_) {}
      return rects;
    };

    const overlaps = (a, b) =>
      !(a.right <= b.left || a.left >= b.right || a.bottom <= b.top || a.top >= b.bottom);

    const registrable = (host) => {
      const parts = String(host || '').toLowerCase().split('.').filter(Boolean);
      return parts.length <= 2 ? parts.join('.') : parts.slice(-2).join('.');
    };

    const isRealChallenge = (el) => {
      try {
        if (el.matches && el.matches(REAL_CHALLENGE)) return true;
        if (el.querySelector && el.querySelector(REAL_CHALLENGE)) return true;
        if (el.closest && el.closest(REAL_CHALLENGE)) return true;
      } catch (_) {}
      return false;
    };

    // يرجع 0 لو العنصر ليس تراكباً إعلانياً، وإلا درجة ثقة.
    const suspicion = (el) => {
      try {
        if (!el || el.nodeType !== 1) return 0;
        if (el.hasAttribute && el.hasAttribute('data-sports-player-blocked-ad')) return 0;
        if (isRealChallenge(el)) return 0;
        // لا نلمس أبداً عنصراً يحتضن الفيديو نفسه.
        if (el.querySelector && el.querySelector('video,audio')) return 0;

        const style = getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return 0;
        if (parseFloat(style.opacity || '1') < 0.05) return 0;

        const rect = el.getBoundingClientRect();
        if (rect.width < 60 || rect.height < 40) return 0;

        const videos = videoRects();
        if (!videos.length) return 0;
        if (!videos.some((v) => overlaps(rect, v))) return 0;

        // --- البوابة الإلزامية ---
        const pageHost = registrable(location.hostname);
        let external = 0;
        let controls = 0;
        try {
          el.querySelectorAll('a,button,[role="button"],[onclick]').forEach((node) => {
            controls++;
            const target = ((node.getAttribute && node.getAttribute('target')) || '').toLowerCase();
            if (target === '_blank' || target === '_new') external++;
            const href = node.getAttribute && node.getAttribute('href');
            if (href && /^https?:/i.test(href)) {
              try {
                if (registrable(new URL(href, location.href).hostname) !== pageHost) external++;
              } catch (_) {}
            }
          });
        } catch (_) {}
        let insidePlayer = false;
        try { insidePlayer = !!(el.closest && el.closest(PLAYER_BOX)); } catch (_) {}
        if (external === 0 && insidePlayer) return 0;

        // --- الترجيح ---
        let score = 0;
        const position = style.position;
        if (position === 'fixed' || position === 'absolute' || position === 'sticky') score += 20;
        const zIndex = parseInt(style.zIndex || '0', 10);
        if (zIndex >= 100) score += 20;
        else if (zIndex >= 10) score += 10;
        if (external > 0) score += 40;

        const appearedAt = bornAt.get(el);
        if (playbackStartedAt && appearedAt && appearedAt >= playbackStartedAt) score += 30;

        if (controls >= 1 && controls <= 3) score += 10;
        const text = ((el.innerText || '') + '').trim();
        if (text.length > 0 && text.length <= 200) score += 10;

        // تراكب بوسط الفيديو (لا شريط تحكم بحافته)
        const v = videos[0];
        if (rect.top > v.top + v.height * 0.05 && rect.bottom < v.bottom - v.height * 0.02) {
          score += 15;
        }
        return score;
      } catch (_) {
        return 0;
      }
    };

    const neutralize = (el, score) => {
      try {
        el.setAttribute('data-sports-player-blocked-ad', '1');
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
        report({ type: 'overlay_ad_blocked', score: score, tag: el.tagName || '' });
      } catch (_) {}
    };

    const THRESHOLD = 75;

    // تشخيص: تراكب بدا مريباً لكنه لم يبلغ العتبة. بدون هذا، أي إعلان ينجو
    // لا يترك أثراً بالسجل إطلاقاً (تراكب DOM بحت، لا حدث شبكة ولا تنقّل)،
    // فتتحوّل كل جولة إصلاح لتخمين. يُبلَّغ مرة واحدة لكل عنصر فقط.
    const reportedNearMiss = new WeakSet();
    const reportNearMiss = (el, score) => {
      try {
        if (score <= 0 || reportedNearMiss.has(el)) return;
        reportedNearMiss.add(el);
        const rect = el.getBoundingClientRect();
        const text = ((el.innerText || '') + '').trim().slice(0, 60);
        report({
          type: 'overlay_ad_spared',
          score: score,
          threshold: THRESHOLD,
          tag: el.tagName || '',
          cls: String(el.className || '').slice(0, 60),
          w: Math.round(rect.width),
          h: Math.round(rect.height),
          text: text,
        });
      } catch (_) {}
    };

    const sweep = () => {
      notePlayback();
      try {
        const roots = [];
        if (document.body) {
          Array.prototype.push.apply(roots, Array.from(document.body.children));
        }
        // كل عنصر مُلحَق حديثاً (سجّله المراقب) يُفحَص أيضاً ولو كان عميقاً.
        recent.forEach((el) => roots.push(el));
        const seen = new Set();
        roots.forEach((el) => {
          if (!el || seen.has(el)) return;
          seen.add(el);
          const score = suspicion(el);
          if (score >= THRESHOLD) {
            neutralize(el, score);
          } else {
            reportNearMiss(el, score);
          }
        });
      } catch (_) {}
    };

    // عناصر أُضيفت للصفحة مؤخراً — أقوى إشارة على تراكب مُقحَم بعد التشغيل.
    let recent = [];
    try {
      new MutationObserver((records) => {
        const now = Date.now();
        records.forEach((record) => {
          record.addedNodes && record.addedNodes.forEach((node) => {
            if (!node || node.nodeType !== 1) return;
            bornAt.set(node, now);
            recent.push(node);
          });
        });
        if (recent.length > 60) recent = recent.slice(-60);
        sweep();
      }).observe(document.documentElement || document, { childList: true, subtree: true });
    } catch (_) {}

    sweep();
    try {
      window.__sportsPlayerTimers = window.__sportsPlayerTimers || [];
      window.__sportsPlayerTimers.push(setInterval(sweep, 1500));
    } catch (_) {}

    // نقطة دخول يدوية: زر النجاة بواجهة Flutter يستدعيها مباشرة.
    window.__sportsPlayerSweepOverlays = sweep;
  } catch (_) {}
})();''';

/// الوصول لما **داخل** الإطارات من نفس الأصل (same-origin).
///
/// جافاسكربتنا يعمل بالإطار الرئيسي فقط، ويستعلم `document` مباشرةً — فلو
/// كان المشغّل الحقيقي داخل `<iframe>` **من نفس دومين الصفحة**، يبقى
/// خفياً تماماً رغم أن المتصفح يسمح لنا بالوصول إليه بالكامل.
///
/// مؤكَّد بسجل فعلي (مسلسل تركي، `ww4.3ick.club`): المشغّل داخل
/// `/embed/1/207438/2/` بنفس الدومين، فلم يُنقَر زر التشغيل ولم يُلتقط أي
/// مصدر طوال 16 دورة اكتشاف (`framework=0 generic=2 mediaHits=0`)، وكان
/// المرشّح الوحيد ملف ووردبريس `wlwmanifest.xml`.
///
/// هذا السكربت يدخل كل إطار من نفس الأصل (متداخلاً) ويقوم بثلاثة أمور:
/// عناصر الوسائط ومصادرها، وسجل الشبكة الخاص بالإطار
/// (`performance.getEntriesByType`) الذي يكشف قائمة m3u8 التي طلبها
/// المشغّل الداخلي، ونقرة تشغيل واحدة آمنة. الإطارات من أصل مختلف
/// يتجاوزها المتصفح تلقائياً (استثناء صامت) — لا محاولة تجاوز إطلاقاً.
const String kSameOriginFrameProbeScript = r'''(() => {
  try {
    if (window.__sportsPlayerFrameProbe) return;
    window.__sportsPlayerFrameProbe = true;

    const report = (payload) => {
      try {
        if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
          window.SportsPlayerSource.postMessage(JSON.stringify(payload));
        }
      } catch (_) {}
    };

    const mediaLike = (url) => {
      const value = String(url || '');
      if (!/^https?:\/\//i.test(value)) return false;
      return /\.(m3u8|m3u|mpd|mp4|m4v|webm|ts|m4s)(?:$|[?#])/i.test(value) ||
             /(master|playlist|manifest|hls)(?:[.?&=\/]|$)/i.test(value);
    };

    const announce = (url, frameUrl) => {
      if (!mediaLike(url)) return;
      report({
        type: 'hls_candidate',
        url: String(url),
        source: 'same-origin-frame',
        mime: '',
        pageUrl: location.href,
        frameUrl: frameUrl || location.href,
        referer: document.referrer || location.href
      });
    };

    // يرجع مستند الإطار لو كان من نفس الأصل، وإلا null (بلا أي محاولة تجاوز).
    const sameOriginDoc = (frame) => {
      try {
        const doc = frame.contentDocument;
        if (!doc || !doc.location) return null;
        return doc;
      } catch (_) {
        return null;
      }
    };

    const probeDoc = (doc, win, depth) => {
      if (!doc || depth > 3) return;
      const frameUrl = (doc.location && doc.location.href) || '';

      try {
        doc.querySelectorAll('video,audio,source').forEach((el) => {
          announce(el.currentSrc || el.src || el.getAttribute('src'), frameUrl);
        });
      } catch (_) {}

      // سجل شبكة الإطار نفسه — يكشف ما طلبه المشغّل الداخلي فعلاً.
      try {
        if (win && win.performance && win.performance.getEntriesByType) {
          win.performance.getEntriesByType('resource').forEach((entry) => {
            announce(entry.name, frameUrl);
          });
        }
      } catch (_) {}

      // نقرة تشغيل واحدة داخل الإطار (نفس تحفّظات الإطار الرئيسي).
      try {
        if (!win.__sportsPlayerFrameClicked) {
          const video = doc.querySelector('video');
          if (video && video.paused && video.readyState >= 1) {
            win.__sportsPlayerFrameClicked = true;
            try { video.muted = true; } catch (_) {}
            const promise = video.play();
            if (promise && promise.catch) promise.catch(() => {});
            report({ type: 'same_origin_frame_played', frameUrl: frameUrl });
          } else {
            const button = doc.querySelector(
              '.jw-icon-playback,.vjs-big-play-button,.plyr__control--overlaid,[class*="play" i][class*="button" i],button[aria-label*="play" i]');
            if (button) {
              win.__sportsPlayerFrameClicked = true;
              button.click();
              report({ type: 'same_origin_frame_played', frameUrl: frameUrl });
            }
          }
        }
      } catch (_) {}

      // إطارات متداخلة بنفس الأصل.
      try {
        doc.querySelectorAll('iframe').forEach((frame) => {
          const inner = sameOriginDoc(frame);
          if (inner) probeDoc(inner, frame.contentWindow, depth + 1);
        });
      } catch (_) {}
    };

    const run = () => {
      try {
        document.querySelectorAll('iframe').forEach((frame) => {
          const doc = sameOriginDoc(frame);
          if (doc) probeDoc(doc, frame.contentWindow, 1);
        });
      } catch (_) {}
    };

    run();
    try {
      window.__sportsPlayerTimers = window.__sportsPlayerTimers || [];
      window.__sportsPlayerTimers.push(setInterval(run, 1200));
    } catch (_) {}
  } catch (_) {}
})();''';

/// يُسكِت الصفحة بالكامل بعد أن يفوز التشغيل الأصلي (ExoPlayer).
///
/// **سبب وجوده — مؤكَّد بسجل تشخيص**: بعد
/// `PLAY_SERVER_QUALITY_SUCCESS ... final state: NATIVE` عند الثانية 35.5،
/// استمر السجل يمتلئ حتى آخره بـ`MEDIA_RESOURCE` و`JWPLAYER_PLAYER_DETECTED`
/// **كل ثانية تقريباً**. أي أن خمسة مؤقّتات مُحقَنة (450ms، 900ms×2،
/// 1200ms، 1800ms) بقيت تمسح الـDOM وتعبر جسر جافاسكربت←Dart وتكتب بالسجل
/// طوال المشاهدة — على الخيط نفسه الذي يرسم الفيديو. ومعها بقي مشغّل
/// الصفحة يسحب نفس الفيديو بالتوازي.
///
/// بعد فوز التشغيل الأصلي لا شيء من هذا له معنى: الصفحة مخفية تماماً
/// (`_isWebSource = false`) ولا أحد يراها. نوقف المؤقّتات والمراقبات
/// ونوقف أي وسائط، **لكن نُبقي المستند نفسه حياً** لأن إنقاذ المانفست
/// (`_relayManifestViaWebView`) قد يحتاج جلسته الحقيقية لاحقاً لو تعثّر
/// التشغيل.
const String kQuiesceWebPageScript = r"""(() => {
  try {
    (window.__sportsPlayerTimers || []).forEach((id) => {
      try { clearInterval(id); } catch (_) {}
    });
    window.__sportsPlayerTimers = [];
  } catch (_) {}
  try {
    (window.__sportsPlayerObservers || []).forEach((o) => {
      try { o.disconnect(); } catch (_) {}
    });
    window.__sportsPlayerObservers = [];
  } catch (_) {}
  try {
    document.querySelectorAll('video,audio').forEach((v) => {
      try { v.muted = true; v.pause(); } catch (_) {}
    });
  } catch (_) {}
  try {
    if (typeof jwplayer === 'function') {
      const jw = jwplayer();
      if (jw && typeof jw.pause === 'function') jw.pause(true);
    }
  } catch (_) {}
})();""";
