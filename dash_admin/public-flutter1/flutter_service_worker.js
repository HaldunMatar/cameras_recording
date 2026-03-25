'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"version.json": "40e3048bb25d055ea44bdb745e52ae93",
"index.html": "cbba2c0109306a83d16dfef66468e837",
"/": "cbba2c0109306a83d16dfef66468e837",
"main.dart.js": "5c981f8e1bc95916bdac46c29a3c34e2",
"flutter.js": "c71a09214cb6f5f8996a531350400a9a",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "c238b2d331c2996a44e1deaf58d01a94",
"assets/AssetManifest.json": "c26e1426d042192a996db7cf2ded7b7e",
"assets/NOTICES": "8a83c679ac219451a80340827e3a7f77",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "0f5bac1c9f831808117b7d5e483c81f8",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "89ed8f4e49bcdfc0b5bfc9b24591e347",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "d6885727caf1775a50bac8c210b781a4",
"assets/fonts/MaterialIcons-Regular.otf": "81247b8e14b218c78ef0776a3973a597",
"assets/assets/ar.png": "9369c7cca79f3ad93018256cc2016a2d",
"assets/assets/images/userprofile.png": "ee87b4f6ed3235e9f7a2c9821211f73a",
"assets/assets/images/ar.png": "9369c7cca79f3ad93018256cc2016a2d",
"assets/assets/images/reports.png": "ef9bf56b0e64f3c0aa7c127027b639eb",
"assets/assets/images/reports.jpeg": "64f46ffc222acaeb9139642a640f03af",
"assets/assets/images/worksafety.png": "a9132daacb93befe7009abe233919c36",
"assets/assets/images/logotechniaa.png": "ced7e6908bad95c37e3f2dd6ee11a10e",
"assets/assets/images/MA%2520INSIGHTS.png": "1f9e18c6189c666ae0f6cac8c8295b49",
"assets/assets/images/Models/ma-insights-models-pose%2520estimation.png": "488e19a7d8678821d7c12b22739f1749",
"assets/assets/images/Models/shoplifting.webp": "a383f61cb48f904df9c48e617077fe5e",
"assets/assets/images/Models/visitors.jpg.webp": "7dcbc64b8d0456f4e034fcbb203c3248",
"assets/assets/images/Models/worksafety.png": "a9132daacb93befe7009abe233919c36",
"assets/assets/images/Models/firemodel.jpeg": "002d2a4f8c60d3d5156861e7a993e70d",
"assets/assets/images/Models/modelsobjectcounting.png": "902bc3c5d43643ca4230592eaa0240d2",
"assets/assets/images/Models/ma-insights-models-car-parkings%2520copy.jpg": "bbffdc909e8c72483b0aacb6c1970b69",
"assets/assets/images/Models/ma-insights-models-object-counting%2520copy.jpg": "902bc3c5d43643ca4230592eaa0240d2",
"assets/assets/images/Models/ma-insights-models-car-parkings.png": "bbffdc909e8c72483b0aacb6c1970b69",
"assets/assets/images/Models/kitchen.png": "33e7a44bc5fc62fc8bab43e55b79d4a5",
"assets/assets/images/Models/ma-insights-models-car-speed-estimation%2520copy.jpg": "b8bb5026e2f3741e7dbe338df0d393f9",
"assets/assets/images/Models/ma-insights-models-car-speed-estimation.png": "b8bb5026e2f3741e7dbe338df0d393f9",
"assets/assets/images/Models/shoplifting.jpg": "a383f61cb48f904df9c48e617077fe5e",
"assets/assets/images/Models/heatmap.png": "bd7e3da25a27f7eae9f8598a2037ba43",
"assets/assets/images/Models/heatmap.jpg": "18f91a5cc0c6a1b9d1f92ad0ed812786",
"assets/assets/images/Models/inout.jpg": "ab56eb6be656ac57282ec2e2f2853561",
"assets/assets/images/firemodel.jpeg": "b576c72a9f15aa2529a34e17395ce78a",
"assets/assets/images/modelsobjectcounting.png": "902bc3c5d43643ca4230592eaa0240d2",
"assets/assets/images/logo1.png": "f1188da4234310ce0eae4db66d02d33a",
"assets/assets/images/dwell.png": "3bad323f89ac7b34a0351f16e4e519b8",
"assets/assets/images/logo.png": "9ee4301f262d992c018853410099a1ce",
"assets/assets/images/parkingmodel.png": "8d5e137487632ccf42a8adf649e703ac",
"assets/assets/images/MA%2520INSIGHTS%2520copy.png": "1f9e18c6189c666ae0f6cac8c8295b49",
"assets/assets/images/speedmodel.png": "6f29d28b8756c30061bb7ff5761cd275",
"assets/assets/images/modelinoutcounting11.png": "9126bfb763c814ad276efe8951be30b5",
"assets/assets/images/ma-insights-models-car-parkings.png": "bbffdc909e8c72483b0aacb6c1970b69",
"assets/assets/images/ma-insights-models-pose-estimation.png": "488e19a7d8678821d7c12b22739f1749",
"assets/assets/images/ma-insights-models-car-speed-estimation.png": "b8bb5026e2f3741e7dbe338df0d393f9",
"assets/assets/images/logo.svg": "c15a19f564ea26954acfd25dfd365c2c",
"assets/assets/images/linearchart.png": "d8b4999320045415d1f4d12b8895f930",
"assets/assets/images/countingmodel.png": "c5b15c5ed000f7d34cb5bd67ccf04f83",
"assets/assets/en.png": "2b4fb0f6f004af105c1d52a93046d85b",
"assets/assets/icons/Search.svg": "396d519c18918ed763d741f4ba90243a",
"assets/assets/icons/google_drive.svg": "9a3005a58d47a11bfeffc11ddd3567c1",
"assets/assets/icons/menu_setting.svg": "d0e24d5d0956729e0e2ab09cb4327e32",
"assets/assets/icons/menu_dashbord.svg": "b2cdf62e9ce9ca35f3fc72f1c1fcc7d4",
"assets/assets/icons/doc_file.svg": "552a02a5a3dbaee682de14573f0ca9f3",
"assets/assets/icons/unknown.svg": "b2f3cdc507252d75dea079282f14614f",
"assets/assets/icons/menu_task.svg": "1a02d1c14f49a765da34487d23a3093b",
"assets/assets/icons/menu_profile.svg": "fe56f998a7c1b307809ea3653a1b62f9",
"assets/assets/icons/menu_store.svg": "2fd4ae47fd0fca084e50a600dda008cd",
"assets/assets/icons/sound_file.svg": "fe212d5edfddd0786319edf50601ec73",
"assets/assets/icons/pdf_file.svg": "ca854643eeee7bedba7a1d550e2ba94f",
"assets/assets/icons/drop_box.svg": "3295157e194179743d6093de9f1ff254",
"assets/assets/icons/xd_file.svg": "38913b108e39bcd55988050d2d80194c",
"assets/assets/icons/menu_tran.svg": "6c95fa7ae6679737dc57efd2ccbb0e57",
"assets/assets/icons/media.svg": "059dfe46bd2d92e30bf361c2f7055c3b",
"assets/assets/icons/car.png": "56ac3e25717dc987a93e7a5cf3edb46d",
"assets/assets/icons/menu_doc.svg": "09673c2879de2db9646345011dbaa7bb",
"assets/assets/icons/car.svg": "6b312b8b54735d07e68f5a8fe2149e05",
"assets/assets/icons/Figma_file.svg": "0ae328b79325e7615054aed3147c81f9",
"assets/assets/icons/menu_notification.svg": "460268d6e4bdeab56538d7020cc4b326",
"assets/assets/icons/logo.svg": "b3af0c077a73709c992d7e075b76ce33",
"assets/assets/icons/media_file.svg": "2ac15c968f8a8cea571a0f3e9f238a66",
"assets/assets/icons/folder.svg": "40a82e74e930ac73aa6ccb85d8c5a29c",
"assets/assets/icons/Documents.svg": "51896b51d35e28711cf4bd218bde185d",
"assets/assets/icons/excle_file.svg": "dc91b258ecf87f5731fb2ab9ae15a3ec",
"assets/assets/icons/one_drive.svg": "aa908c0a29eb795606799385cdfc8592",
"canvaskit/skwasm.js": "445e9e400085faead4493be2224d95aa",
"canvaskit/skwasm.js.symbols": "741d50ffba71f89345996b0aa8426af8",
"canvaskit/canvaskit.js.symbols": "38cba9233b92472a36ff011dc21c2c9f",
"canvaskit/skwasm.wasm": "e42815763c5d05bba43f9d0337fa7d84",
"canvaskit/chromium/canvaskit.js.symbols": "4525682ef039faeb11f24f37436dca06",
"canvaskit/chromium/canvaskit.js": "43787ac5098c648979c27c13c6f804c3",
"canvaskit/chromium/canvaskit.wasm": "f5934e694f12929ed56a671617acd254",
"canvaskit/canvaskit.js": "c86fbd9e7b17accae76e5ad116583dc4",
"canvaskit/canvaskit.wasm": "3d2a2d663e8c5111ac61a46367f751ac",
"canvaskit/skwasm.worker.js": "bfb704a6c714a75da9ef320991e88b03"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
