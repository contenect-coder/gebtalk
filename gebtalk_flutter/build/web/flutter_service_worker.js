'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {".git/objects/10/60d9da5b25f05ed9bdc8be25f89df8629363a1": "aeb55affdcea289c2c86749adda2cf17",
".git/objects/17/11225809e7ad8874d7bacf932fe059fd050456": "60caeead1eaa085f8a7ad9fe67dd205c",
".git/objects/1a/d7683b343914430a62157ebf451b9b2aa95cac": "94fdc36a022769ae6a8c6c98e87b3452",
".git/objects/22/1736fed2cd3a194ccb99b2387e0899667a8d21": "3b26e7276c9a541df88863f611b0bb98",
".git/objects/23/10af501ff54dd15f36787e0fbd6bda8756a2ab": "e33b50eb129ad664604743cdf55c4944",
".git/objects/23/3d1ccc44e1c50ffdf01df9548d216a65d456f7": "e4a516487d69f05faaba67e6e459a406",
".git/objects/26/dcf7c474f30142836db1dfa541a7abb3376548": "714303260b46043cd730f17710b751fc",
".git/objects/2e/c5134925394a32228ce710d9a7042f2e997146": "01591cb712964cae4c8cd6add190954b",
".git/objects/31/0011056ef34a67f18ede280341582945b15628": "5131048766b5b56dcbcecb2a261c8495",
".git/objects/36/ac1d986a4c317db2849d297ca95fc7e009f7d4": "0a5f5563313c43312a8429540cf88a24",
".git/objects/40/637acc8890cdb88b28caade181fed4789763ac": "41e37e0094d4b1d5709bcfa98b23ad2f",
".git/objects/40/90c170d80baf37334a9c2a3c57e693413bb026": "715cc432e8ba701941353a250691bfe4",
".git/objects/4c/51fb2d35630595c50f37c2bf5e1ceaf14c1a1e": "a20985c22880b353a0e347c2c6382997",
".git/objects/51/426d31270c09985c40cba2141ef1b2e5d30544": "ac6d309223b0eab1054845a56754896b",
".git/objects/53/18a6956a86af56edbf5d2c8fdd654bcc943e88": "a686c83ba0910f09872b90fd86a98a8f",
".git/objects/53/3d2508cc1abb665366c7c8368963561d8c24e0": "4592c949830452e9c2bb87f305940304",
".git/objects/57/223c83dd4204a125f5c8663247a0d9d250150d": "d4491474c5ada7fc99409336c49f409d",
".git/objects/57/ac362ae3ae6922fc9152533fa160e284b482b1": "5688955abee49ca5b14f2ac5e594ce21",
".git/objects/5c/177b1c9c52e2abb5f8089ae36e3a6583412d46": "a70431496dc8d4087510028666993981",
".git/objects/61/6dd88879fb8f4178db2b9765531d741f2f6e75": "d808ae01370af5cc7304ac6ef879726f",
".git/objects/6b/9862a1351012dc0f337c9ee5067ed3dbfbb439": "85896cd5fba127825eb58df13dfac82b",
".git/objects/6d/4dddc1637ab591a3110179e44db26acf971be0": "29b0a0a10a60fa9146c4916af514f43b",
".git/objects/70/a234a3df0f8c93b4c4742536b997bf04980585": "d95736cd43d2676a49e58b0ee61c1fb9",
".git/objects/71/46e149a5b901926c0d2b9ba386b8303fc0ab73": "d3a4cf30a3ee58b0b532a2b54ed9f2be",
".git/objects/73/c63bcf89a317ff882ba74ecb132b01c374a66f": "6ae390f0843274091d1e2838d9399c51",
".git/objects/7e/8e36cc91335407b7b12d57c6a48a27933b9877": "8b8682524acefb8719a2f73f408d92b5",
".git/objects/88/cfd48dff1169879ba46840804b412fe02fefd6": "e42aaae6a4cbfbc9f6326f1fa9e3380c",
".git/objects/8a/aa46ac1ae21512746f852a42ba87e4165dfdd1": "1d8820d345e38b30de033aa4b5a23e7b",
".git/objects/8e/3c7d6bbbef6e7cefcdd4df877e7ed0ee4af46e": "025a3d8b84f839de674cd3567fdb7b1b",
".git/objects/93/1ecf4cc09f74244a3bbeec93d90e7779146427": "dc186531ce58f343087cf2a9e951a65c",
".git/objects/9b/d3accc7e6a1485f4b1ddfbeeaae04e67e121d8": "784f8e1966649133f308f05f2d98214f",
".git/objects/ad/ddb3c7705652060f7e45ca7b15b9dcd654882b": "2cd3e46b87fe8067e686c72616a9b0e1",
".git/objects/b7/49bfef07473333cf1dd31e9eed89862a5d52aa": "36b4020dca303986cad10924774fb5dc",
".git/objects/b9/2a0d854da9a8f73216c4a0ef07a0f0a44e4373": "f62d1eb7f51165e2a6d2ef1921f976f3",
".git/objects/b9/6a5236065a6c0fb7193cb2bb2f538b2d7b4788": "4227e5e94459652d40710ef438055fe5",
".git/objects/bf/537d40dfebda6b3880cd632a913fdf33c4bf95": "858097db26d14c8728cd990c75c3f143",
".git/objects/c6/2d9c338e1a83945da423c2c4b81b67105cd360": "06df3f0e9d691271a5b37f4108b0f8d6",
".git/objects/c8/08fb85f7e1f0bf2055866aed144791a1409207": "92cdd8b3553e66b1f3185e40eb77684e",
".git/objects/cc/16f2204af126a28c1d450818794ddf57abd913": "c58e05d126d4a4dd752119f0b3e2be9e",
".git/objects/d4/3532a2348cc9c26053ddb5802f0e5d4b8abc05": "3dad9b209346b1723bb2cc68e7e42a44",
".git/objects/d6/9c56691fbdb0b7efa65097c7cc1edac12a6d3e": "868ce37a3a78b0606713733248a2f579",
".git/objects/d7/7cfefdbe249b8bf90ce8244ed8fc1732fe8f73": "9c0876641083076714600718b0dab097",
".git/objects/dc/11fdb45a686de35a7f8c24f3ac5f134761b8a9": "761c08dfe3c67fe7f31a98f6e2be3c9c",
".git/objects/e0/7ac7b837115a3d31ed52874a73bd277791e6bf": "74ebcb23eb10724ed101c9ff99cfa39f",
".git/objects/e2/7d1b98aa2943ed9d768016cf1f36a025fd18ef": "862495782e0e8018170d2a3387c1c864",
".git/objects/e6/9de29bb2d1d6434b8b29ae775ad8c2e48c5391": "c70c34cbeefd40e7c0149b7a0c2c64c2",
".git/objects/e9/94225c71c957162e2dcc06abe8295e482f93a2": "2eed33506ed70a5848a0b06f5b754f2c",
".git/objects/eb/9b4d76e525556d5d89141648c724331630325d": "37c0954235cbe27c4d93e74fe9a578ef",
".git/objects/ef/5066a8a2091c00d4b3ebc0f9c053c2c5384232": "0dd8f4e54e5d6fab4da790d08ab50a01",
".git/objects/f2/04823a42f2d890f945f70d88b8e2d921c6ae26": "6b47f314ffc35cf6a1ced3208ecc857d",
".git/objects/f5/72b90ef57ee79b82dd846c6871359a7cb10404": "e68f5265f0bb82d792ff536dcb99d803",
"404.html": "1b5a1b57e1a198a71679307b162338d9",
"assets/AssetManifest.bin": "7a1b8525354557cd52fbb0b7f78e3a76",
"assets/AssetManifest.bin.json": "d806d2d75594e982ec15c7bcde102d57",
"assets/AssetManifest.json": "915d7a2a3d7a85892e4216788acb4289",
"assets/assets/fonts/GoogleSans-Bold.ttf": "2c062fe579b94c7eac7c2e2fdd6b57f1",
"assets/assets/fonts/GoogleSans-Regular.ttf": "0393caf48023921cd39f35b83f17c9d6",
"assets/assets/fonts/ProductSans-Bold.ttf": "2c062fe579b94c7eac7c2e2fdd6b57f1",
"assets/assets/fonts/ProductSans-Regular.ttf": "0393caf48023921cd39f35b83f17c9d6",
"assets/assets/images/logo.png": "402abc80aacca347e786d71eef049bb2",
"assets/assets/images/logo.svg": "a23fb845b926beceb5f99baa444b7e5b",
"assets/assets/images/logo_icon.png": "402abc80aacca347e786d71eef049bb2",
"assets/FontManifest.json": "924d3ba51db6a89e30290e6431c852bc",
"assets/fonts/MaterialIcons-Regular.otf": "db5d02200cb22672cc2c91c33cb2cf40",
"assets/NOTICES": "4e1521af71d9ac264f10ea776ded4eb0",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/canvaskit.js.symbols": "bdcd3835edf8586b6d6edfce8749fb77",
"canvaskit/canvaskit.wasm": "7a3f4ae7d65fc1de6a6e7ddd3224bc93",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "b61b5f4673c9698029fa0a746a9ad581",
"canvaskit/chromium/canvaskit.wasm": "f504de372e31c8031018a9ec0a9ef5f0",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/skwasm.js.symbols": "e72c79950c8a8483d826a7f0560573a1",
"canvaskit/skwasm.wasm": "39dd80367a4e71582d234948adc521c0",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"flutter_bootstrap.js": "74dc334c81e4ed443c9d7e6e0d90ed29",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "3623c0befe419416c3a572149311c28b",
"/": "3623c0befe419416c3a572149311c28b",
"main.dart.js": "49f5adc7cc9cfeb3e95dab80ff49c8e0",
"manifest.json": "47dd8fd61f3ab206c05447c370f0268a",
"sw.js": "b61e7156b14d7d9a6535b5e07f1cdc67",
"version.json": "09801c2f728540f0fe0f56ed42f89187",
"_redirects": "a4f4a22009e0b3d47dfc13e36b06d767"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
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
