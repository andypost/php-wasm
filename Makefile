ENV_FILE?=.env

-include ${ENV_FILE}

_UID:=$(shell echo $$UID)
_GID:=$(shell echo $$UID)
UID?=${_UID}
GID?=${_GID}

SHELL=bash -euxo pipefail

PHP_DIST_DIR_DEFAULT ?=./dist
PHP_DIST_DIR ?=${PHP_DIST_DIR_DEFAULT}
VRZNO_DEV_PATH=~/projects/vrzno

ENVIRONMENT    ?=web
INITIAL_MEMORY ?=1024MB
PRELOAD_ASSETS ?=preload/
ASSERTIONS     ?=0
OPTIMIZE       ?=3
RELEASE_SUFFIX ?=

PHP_VERSION    ?=8.2
PHP_BRANCH     ?=php-8.2.11
PHP_AR         ?=libphp

# PHP_VERSION    ?=7.4
# PHP_BRANCH     ?=php-7.4.20
# PHP_AR         ?=libphp7

VRZNO_BRANCH   ?=DomAccess8.2
ICU_TAG        ?=release-74-rc
LIBXML2_TAG    ?=v2.9.10
TIDYHTML_TAG   ?=5.6.0
ICONV_TAG      ?=v1.17
SQLITE_VERSION ?=3410200
SQLITE_DIR     ?=sqlite3.41-src
TIMELIB_BRANCH ?=2018.01

PKG_CONFIG_PATH?=/src/lib/lib/pkgconfig

DOCKER_ENV=PHP_DIST_DIR=${PHP_DIST_DIR} docker-compose -p phpwasm run --rm \
	-e PKG_CONFIG_PATH=${PKG_CONFIG_PATH} \
	-e PRELOAD_ASSETS='${PRELOAD_ASSETS}' \
	-e INITIAL_MEMORY=${INITIAL_MEMORY}   \
	-e ENVIRONMENT=${ENVIRONMENT}         \
	-e PHP_BRANCH=${PHP_BRANCH}           \
	-e EMCC_CORES=`nproc`

DOCKER_ENV_SIDE=docker-compose -p phpwasm run --rm \
	-e PRELOAD_ASSETS='${PRELOAD_ASSETS}' \
	-e INITIAL_MEMORY=${INITIAL_MEMORY}   \
	-e ENVIRONMENT=${ENVIRONMENT}         \
	-e PHP_BRANCH=${PHP_BRANCH}           \
	-e EMCC_CORES=`nproc`                 \
	-e CFLAGS=" -I/root/lib/include " \
	-e EMCC_FLAGS=" -sSIDE_MODULE=1 -sERROR_ON_UNDEFINED_SYMBOLS=0 "

DOCKER_RUN           =${DOCKER_ENV} emscripten-builder
DOCKER_RUN_USER      =${DOCKER_ENV} -e UID=${UID} -e GID=${GID} emscripten-builder
DOCKER_RUN_IN_PHP    =${DOCKER_ENV} -w /src/third_party/php${PHP_VERSION}-src/ emscripten-builder
DOCKER_RUN_IN_PHPSIDE=${DOCKER_ENV_SIDE} -w /src/third_party/php${PHP_VERSION}-src/ emscripten-builder
DOCKER_RUN_IN_ICU4C  =${DOCKER_ENV} -w /src/third_party/libicu-src/icu4c/source/ emscripten-builder
DOCKER_RUN_IN_LIBXML =${DOCKER_ENV} -w /src/third_party/libxml2/ emscripten-builder
DOCKER_RUN_IN_SQLITE =${DOCKER_ENV_SIDE} -w /src/third_party/${SQLITE_DIR}/ emscripten-builder
DOCKER_RUN_IN_TIDY   =${DOCKER_ENV_SIDE} -w /src/third_party/tidy-html5/ emscripten-builder
DOCKER_RUN_IN_ICU    =${DOCKER_ENV_SIDE} -w /src/third_party/libicu-src/icu4c/source emscripten-builder
DOCKER_RUN_IN_ICONV  =${DOCKER_ENV_SIDE} -w /src/third_party/libiconv-1.17/ emscripten-builder
DOCKER_RUN_IN_TIMELIB=${DOCKER_ENV_SIDE} -w /src/third_party/timelib/ emscripten-builder

TIMER=(which pv > /dev/null && pv --name '${@}' || cat)
.PHONY: all web js cjs mjs clean php-clean deep-clean show-ports show-versions show-files hooks image push-image pull-image package dist demo

MJS=build/php-web-drupal.mjs build/php-web.mjs build/php-webview.mjs build/php-node.mjs build/php-shell.mjs build/php-worker.mjs
CJS=build/php-web-drupal.js  build/php-web.js  build/php-webview.js  build/php-node.js  build/php-shell.js  build/php-worker.js

all: package js
cjs: ${CJS}
mjs: ${MJS}
js: cjs mjs
	@ echo -e "\e[33;4mBuilding JS\e[0m"
	npx babel source --out-dir .
	find source -name "*.js" | while read JS; do \
		cp $${JS} $$(basename $${JS%.js}.mjs); \
		sed -i -E "s~\\b(import.+ from )(['\"])([^'\"]+)\2~\1\2\3.mjs\2~g" $$(basename $${JS%.js}.mjs); \
		sed -i -E "s~\\brequire(\()(['\"])([^'\"]+)\2(\))~(await import\1\2\3.mjs\2\4).default~g" $$(basename $${JS%.js}.mjs); \
	done;

package: php-web-drupal.mjs php-web.mjs php-webview.mjs php-node.mjs php-shell.mjs php-worker.js \
         php-web-drupal.js  php-web.js  php-webview.js  php-node.js  php-shell.js php-worker.js

dist: dist/php-web-drupal.mjs dist/php-web.mjs dist/php-webview.mjs dist/php-node.mjs dist/php-shell.mjs dist/php-worker.js \
      dist/php-web-drupal.js  dist/php-web.js  dist/php-webview.js  dist/php-node.js  dist/php-shell.js  dist/php-worker.js

web-drupal: lib/pib_eval.o php-web-drupal.wasm
web: lib/pib_eval.o php-web.wasm
	echo "Done!"

########### Collect & patch the source code. ###########

third_party/${SQLITE_DIR}/sqlite3.c:
	@ echo -e "\e[33;4mDownloading and patching SQLite\e[0m"
	wget -q https://sqlite.org/2023/sqlite-autoconf-${SQLITE_VERSION}.tar.gz
	${DOCKER_RUN} tar -xzf sqlite-autoconf-${SQLITE_VERSION}.tar.gz
	${DOCKER_RUN} rm -r sqlite-autoconf-${SQLITE_VERSION}.tar.gz
	${DOCKER_RUN} rm -rf third_party/${SQLITE_DIR}
	${DOCKER_RUN} mv sqlite-autoconf-${SQLITE_VERSION} third_party/${SQLITE_DIR}
	
third_party/php${PHP_VERSION}-src/.gitignore: third_party/${SQLITE_DIR}/sqlite3.c
	@ echo -e "\e[33;4mDownloading and patching PHP\e[0m"
	${DOCKER_RUN} git clone https://github.com/php/php-src.git third_party/php${PHP_VERSION}-src \
		--branch ${PHP_BRANCH}   \
		--single-branch          \
		--depth 1

third_party/php${PHP_VERSION}-src/patched: third_party/php${PHP_VERSION}-src/.gitignore
	${DOCKER_RUN} git apply --no-index patch/php${PHP_VERSION}.patch
	${DOCKER_RUN} mkdir -p third_party/php${PHP_VERSION}-src/preload/Zend
	${DOCKER_RUN} cp third_party/php${PHP_VERSION}-src/Zend/bench.php third_party/php${PHP_VERSION}-src/preload/Zend
	${DOCKER_RUN} touch third_party/php${PHP_VERSION}-src/patched

ifdef VRZNO_DEV_PATH
third_party/vrzno/vrzno.c: ${VRZNO_DEV_PATH}/vrzno.c
	@ echo -e "\e[33;Importing VRZNO\e[0m"
	@ cp -rfv ${VRZNO_DEV_PATH} third_party/
	@ ${DOCKER_RUN} touch third_party/vrzno/vrzno.c
else
third_party/vrzno/vrzno.c:
	@ echo -e "\e[33;4mDownloading and importing VRZNO\e[0m"
	@ ${DOCKER_RUN} git clone https://github.com/seanmorris/vrzno.git third_party/vrzno \
		--branch ${VRZNO_BRANCH} \
		--single-branch          \
		--depth 1
endif

third_party/php${PHP_VERSION}-src/ext/vrzno/vrzno.c: third_party/vrzno/vrzno.c
	@ ${DOCKER_RUN} cp -rfv third_party/vrzno third_party/php${PHP_VERSION}-src/ext/

third_party/drupal-7.95/README.txt:
	@ echo -e "\e[33;4mDownloading and patching Drupal\e[0m"
	wget -q https://ftp.drupal.org/files/projects/drupal-7.95.zip
	${DOCKER_RUN} unzip drupal-7.95.zip
	${DOCKER_RUN} rm -v drupal-7.95.zip
	${DOCKER_RUN} mv drupal-7.95 third_party/drupal-7.95
	${DOCKER_RUN} git apply --no-index patch/drupal-7.95.patch
	${DOCKER_RUN} cp -r extras/drupal-7-settings.php third_party/drupal-7.95/sites/default/settings.php
	${DOCKER_RUN} cp -r extras/drowser-files/.ht.sqlite third_party/drupal-7.95/sites/default/files/.ht.sqlite
	${DOCKER_RUN} cp -r extras/drowser-files/* third_party/drupal-7.95/sites/default/files
	${DOCKER_RUN} cp -r extras/drowser-logo.png third_party/drupal-7.95/sites/default/logo.png
	${DOCKER_RUN} rm -rf third_party/php${PHP_VERSION}-src/preload/drupal-7.95
	${DOCKER_RUN} mkdir -p third_party/php${PHP_VERSION}-src/preload
	${DOCKER_RUN} cp -r third_party/drupal-7.95 third_party/php${PHP_VERSION}-src/preload/

third_party/libxml2/.gitignore:
	@ echo -e "\e[33;4mDownloading LibXML2\e[0m"
	${DOCKER_RUN} env GIT_SSL_NO_VERIFY=true git clone https://gitlab.gnome.org/GNOME/libxml2.git third_party/libxml2 \
		--branch ${LIBXML2_TAG} \
		--single-branch     \
		--depth 1;

third_party/tidy-html5/.gitignore:
	${DOCKER_RUN} git clone https://github.com/htacg/tidy-html5.git third_party/tidy-html5 \
		--branch ${TIDYHTML_TAG} \
		--single-branch     \
		--depth 1;
	${DOCKER_RUN_IN_TIDY} git apply --no-index ../../patch/tidy-html.patch

# third_party/libicu-src/.gitignore:
# 	${DOCKER_RUN} git clone https://github.com/unicode-org/icu.git third_party/libicu-src \
# 		--branch ${ICU_TAG} \
# 		--single-branch     \
# 		--depth 1;

third_party/libiconv-1.17/README:
	${DOCKER_RUN} wget -q https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
	${DOCKER_RUN} tar -xvzf libiconv-1.17.tar.gz -C third_party
	${DOCKER_RUN} rm libiconv-1.17.tar.gz

########### Build the objects. ###########

lib/lib/libxml2.a: third_party/libxml2/.gitignore
	@ echo -e "\e[33;4mBuilding LibXML2\e[0m"
	${DOCKER_RUN_IN_LIBXML} ./autogen.sh
	${DOCKER_RUN_IN_LIBXML} emconfigure ./configure --with-http=no --with-ftp=no --with-python=no --with-threads=no --enable-shared=no --prefix=/src/lib/
	${DOCKER_RUN_IN_LIBXML} emmake make -j`nproc` EXTRA_CFLAGS='-fPIC -O${OPTIMIZE}'
	${DOCKER_RUN_IN_LIBXML} emmake make install

lib/lib/libsqlite3.a: third_party/${SQLITE_DIR}/sqlite3.c
	@ echo -e "\e[33;4mBuilding LibSqlite3\e[0m"
	${DOCKER_RUN_IN_SQLITE} emconfigure ./configure --with-http=no --with-ftp=no --with-python=no --with-threads=no --enable-shared=no --prefix=/src/lib/
	${DOCKER_RUN_IN_SQLITE} emmake make -j`nproc` EXTRA_CFLAGS='-fPIC -O${OPTIMIZE}'
	${DOCKER_RUN_IN_SQLITE} emmake make install

lib/lib/libtidy.a: third_party/tidy-html5/.gitignore
	@ echo -e "\e[33;4mBuilding LibTidy\e[0m"
	${DOCKER_RUN_IN_TIDY} emcmake cmake . \
		-DCMAKE_INSTALL_PREFIX=/src/lib/ \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="-I/emsdk/upstream/emscripten/system/lib/libc/musl/include/ -fPIC -O${OPTIMIZE}"
	${DOCKER_RUN_IN_TIDY} emmake make;
	${DOCKER_RUN_IN_TIDY} emmake make install;

# lib/lib/libicudata.a: third_party/libicu-src/.gitignore
# 	@ echo -e "\e[33;4mBuilding LibIcu\e[0m"
# 	${DOCKER_RUN_IN_ICU} emconfigure ./configure --prefix=/src/lib/ --enable-icu-config --enable-extras=no --enable-tools=no --enable-samples=no --enable-tests=no --enable-shared=no --enable-static=yes
# 	${DOCKER_RUN_IN_ICU} emmake make clean install

lib/lib/libiconv.a: third_party/libiconv-1.17/README
	@ echo -e "\e[33;4mBuilding LibIconv\e[0m"
	${DOCKER_RUN_IN_ICONV} autoconf
	${DOCKER_RUN_IN_ICONV} emconfigure ./configure --prefix=/src/lib/ --enable-shared=no --enable-static=yes
	${DOCKER_RUN_IN_ICONV} emmake make EMCC_CFLAGS='-fPIC -O${OPTIMIZE}'
	${DOCKER_RUN_IN_ICONV} emmake make install

third_party/php${PHP_VERSION}-src/configured: \
third_party/php${PHP_VERSION}-src/patched \
lib/lib/libxml2.a lib/lib/libtidy.a lib/lib/libiconv.a lib/lib/libsqlite3.a # libicudata.a
	@ echo -e "\e[33;4mConfiguring PHP\e[0m"
	${DOCKER_RUN_IN_PHPSIDE} ./buildconf --force
	${DOCKER_RUN_IN_PHPSIDE} emconfigure ./configure \
		PKG_CONFIG_PATH=${PKG_CONFIG_PATH} \
		--enable-embed=static \
		--prefix=/src/lib/ \
		--with-layout=GNU  \
		--with-libxml      \
		--disable-cgi      \
		--disable-cli      \
		--disable-all      \
		--enable-session   \
		--enable-filter    \
		--enable-calendar  \
		--enable-dom       \
		--disable-rpath    \
		--disable-phpdbg   \
		--without-pear     \
		--with-valgrind=no \
		--without-pcre-jit \
		--enable-bcmath    \
		--enable-json      \
		--enable-ctype     \
		--enable-mbstring  \
		--disable-mbregex  \
		--enable-tokenizer \
		--enable-vrzno     \
		--enable-xml       \
		--enable-simplexml \
		--with-gd          \
		--with-sqlite3     \
		--enable-pdo       \
		--with-pdo-sqlite=/src/lib \
		--with-iconv=/src/lib \
		--with-tidy=/src/lib \
		--disable-fiber-asm
	${DOCKER_RUN_IN_PHPSIDE} touch /src/third_party/php${PHP_VERSION}-src/configured

lib/lib/${PHP_AR}.a: third_party/php${PHP_VERSION}-src/configured third_party/php${PHP_VERSION}-src/patched third_party/php${PHP_VERSION}-src/ext/vrzno/vrzno.c
	@ echo -e "\e[33;4mBuilding PHP\e[0m"
	@ ${DOCKER_RUN_IN_PHPSIDE} rm -rf third_party/php${PHP_VERSION}-src/ext/vrzno/vrzno.o third_party/php${PHP_VERSION}-src/ext/vrzno/vrzno.lo
	@ ${DOCKER_RUN_IN_PHPSIDE} emmake make clean
	@ ${DOCKER_RUN_IN_PHPSIDE} emmake make -j`nproc` EXTRA_CFLAGS='-Wno-int-conversion -Wno-incompatible-function-pointer-types -O${OPTIMIZE}'
	@ ${DOCKER_RUN_IN_PHPSIDE} emmake make install

########### Build the final files. ###########

FINAL_BUILD=${DOCKER_RUN_IN_PHP} emcc -O${OPTIMIZE} -g4 \
	-Wno-int-conversion -Wno-incompatible-function-pointer-types \
	-s EXPORTED_FUNCTIONS='["_pib_init", "_pib_destroy", "_pib_run", "_pib_exec", "_pib_refresh", "_main", "_php_embed_init", "_php_embed_shutdown", "_php_embed_shutdown", "_zend_eval_string", "_exec_callback", "_del_callback"]' \
	-s EXPORTED_RUNTIME_METHODS='["ccall", "UTF8ToString", "lengthBytesUTF8"]' \
	-s ENVIRONMENT=${ENVIRONMENT}    \
	-s MAXIMUM_MEMORY=2048mb         \
	-s INITIAL_MEMORY=${INITIAL_MEMORY} \
	-s ALLOW_MEMORY_GROWTH=1         \
	-s ASSERTIONS=${ASSERTIONS}      \
	-s ERROR_ON_UNDEFINED_SYMBOLS=0  \
	-s EXPORT_NAME="'PHP'"           \
	-s MODULARIZE=1                  \
	-s INVOKE_RUN=0                  \
	-s USE_ZLIB=1                    \
	-I .     \
    -I Zend  \
    -I main  \
    -I TSRM/ \
	-I /src/third_party/libxml2 \
	-I /src/third_party/${SQLITE_DIR} \
	-I ext/pdo_sqlite \
	-I ext/json \
	-I ext/vrzno \
	-o ../../build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.${BUILD_TYPE} \
	--llvm-lto 2                     \
	/src/lib/lib/${PHP_AR}.a \
	/src/lib/lib/libxml2.a   \
	/src/lib/lib/libtidy.a   \
	/src/lib/lib/libiconv.a /src/lib/lib/libcharset.a \
	/src/lib/lib/libsqlite3.a ext/pdo_sqlite/pdo_sqlite.c ext/pdo_sqlite/sqlite_driver.c ext/pdo_sqlite/sqlite_statement.c \
	/src/source/pib_eval.c

# /src/lib/lib/libicudata.a /src/lib/lib/libicui18n.a /src/lib/lib/libicuio.a /src/lib/lib/libicuuc.a

ARCHIVES=lib/lib/libxml2.a lib/lib/libiconv.a lib/lib/libtidy.a lib/lib/libxml2.a lib/lib/libsqlite3.a 
DEPENDENCIES=${ARCHIVES} lib/lib/${PHP_AR}.a source/pib_eval.c
BUILD_TYPE ?=js

build/php-web-drupal.js: ENVIRONMENT=web-drupal
build/php-web-drupal.js: ${DEPENDENCIES} third_party/drupal-7.95/README.txt
	@ echo -e "\e[33;4mBuilding PHP for web (drupal)\e[0m"
	${FINAL_BUILD} --preload-file ${PRELOAD_ASSETS} -s ENVIRONMENT=web

docs-source/app/assets/php-web-drupal.js: ENVIRONMENT=web-drupal
docs-source/app/assets/php-web-drupal.js: build/php-web-drupal.js
	${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.${BUILD_TYPE} ./docs-source/app/assets;
	${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.wasm ./docs-source/app/assets;
	${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.data ./docs-source/app/assets;
	
	# ${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.${BUILD_TYPE} ./docs-source/app/assets;
	# ${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.wasm ./docs-source/app/assets;
	# ${DOCKER_RUN} cp -v build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.data ./docs-source/public;
	
	# ${DOCKER_RUN} chown ${UID}:${GID} \
	# 	./docs-source/app/assets/php-${ENVIRONMENT}${RELEASE_SUFFIX}.${BUILD_TYPE} \
	# 	./docs-source/app/assets/php-${ENVIRONMENT}${RELEASE_SUFFIX}.wasm \
	# 	./docs-source/app/assets/php-${ENVIRONMENT}${RELEASE_SUFFIX}.data \
	# 	./docs-source/public/php-${ENVIRONMENT}${RELEASE_SUFFIX}.${BUILD_TYPE} \
	# 	./docs-source/public/php-${ENVIRONMENT}${RELEASE_SUFFIX}.wasm \
	# 	./docs-source/public/php-${ENVIRONMENT}${RELEASE_SUFFIX}.data

build/php-web-drupal.mjs: BUILD_TYPE=mjs
build/php-web-drupal.mjs: ENVIRONMENT=web-drupal
build/php-web-drupal.mjs: ${DEPENDENCIES} third_party/drupal-7.95/README.txt
	${FINAL_BUILD} --preload-file ${PRELOAD_ASSETS} -s ENVIRONMENT=web

build/php-web.js: ENVIRONMENT=web
build/php-web.js: ${DEPENDENCIES}
	@ echo -e "\e[33;4mBuilding PHP for web\e[0m"
	@ ${FINAL_BUILD}

build/php-web.mjs: BUILD_TYPE=mjs
build/php-web.mjs: ENVIRONMENT=web
build/php-web.mjs: ${DEPENDENCIES}
	@ ${FINAL_BUILD}

build/php-worker.js: ENVIRONMENT=worker
build/php-worker.js: ${DEPENDENCIES}
	@ echo -e "\e[33;4mBuilding PHP for workers\e[0m"
	@ ${FINAL_BUILD}

build/php-worker.mjs: BUILD_TYPE=mjs
build/php-worker.mjs: ENVIRONMENT=worker
build/php-worker.mjs: ${DEPENDENCIES}
	@ ${FINAL_BUILD}

build/php-node.js: ENVIRONMENT=node
build/php-node.js: ${DEPENDENCIES}
	@ echo -e "\e[33;4mBuilding PHP for node\e[0m"
	@ ${FINAL_BUILD}

build/php-node.mjs: BUILD_TYPE=mjs
build/php-node.mjs: ENVIRONMENT=node
build/php-node.mjs: ${DEPENDENCIES}
	@ ${FINAL_BUILD}

build/php-shell.js: ENVIRONMENT=shell
build/php-shell.js: ${DEPENDENCIES}
	@ echo -e "\e[33mBuilding PHP for shell\e[0m"
	@ ${FINAL_BUILD}

build/php-shell.mjs: BUILD_TYPE=mjs
build/php-shell.mjs: ENVIRONMENT=shell
build/php-shell.mjs: ${DEPENDENCIES}
	@ ${FINAL_BUILD}

build/php-webview.js: ENVIRONMENT=webview
build/php-webview.js: ${DEPENDENCIES}
	@ echo -e "\e[33mBuilding PHP for webview\e[0m"
	@ ${FINAL_BUILD}

build/php-webview.mjs: BUILD_TYPE=mjs
build/php-webview.mjs: ENVIRONMENT=webview
build/php-webview.mjs: ${DEPENDENCIES}
	@ ${FINAL_BUILD}

########## Package files ###########

php-web-drupal.js: build/php-web-drupal.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-web-drupal.mjs: build/php-web-drupal.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-web.js: build/php-web.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-web.mjs: build/php-web.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-worker.js: build/php-worker.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-worker.mjs: build/php-worker.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-node.js: build/php-node.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-node.mjs: build/php-node.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-shell.js: build/php-shell.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-shell.mjs: build/php-shell.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-webview.js: build/php-node.js
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

php-webview.mjs: build/php-webview.mjs
	cp $^ $@
	cp $(basename $^).wasm $(basename $@).wasm

########## Dist files ###########

dist/php-web-drupal.js: build/php-web-drupal.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm
	@ ${DOCKER_RUN_USER} cp $(basename $^).data $(basename $@).data

dist/php-web-drupal.mjs: build/php-web-drupal.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-web.js: build/php-web.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-web.mjs: build/php-web.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-worker.js: build/php-worker.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-worker.mjs: build/php-worker.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-node.js: build/php-node.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-node.mjs: build/php-node.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-shell.js: build/php-shell.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-shell.mjs: build/php-shell.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-webview.js: build/php-node.js
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

dist/php-webview.mjs: build/php-webview.mjs
	@ ${DOCKER_RUN_USER} cp $^ $@
	@ ${DOCKER_RUN_USER} cp $(basename $^).wasm $(basename $@).wasm

########### Clerical stuff. ###########

clean:
	# @ ${DOCKER_RUN} rm -fv  *.js *.mjs *.wasm *.data
	@ ${DOCKER_RUN} rm -rf /src/lib/lib/${PHP_AR}.* /src/lib/lib/php /src/lib/include/php
	@ ${DOCKER_RUN_IN_PHP} make clean

php-clean:
	${DOCKER_RUN_IN_PHP} rm -fv configured
	${DOCKER_RUN_IN_PHP} make clean

deep-clean:
	# @ ${DOCKER_RUN} rm -fv  *.js *.mjs *.wasm *.data
	@ ${DOCKER_RUN} rm -rfv \
		third_party/php${PHP_VERSION}-src lib/* build/* \
		third_party/drupal-7.95 third_party/libxml2 third_party/tidy-html5 \
		third_party/libicu-src third_party/${SQLITE_DIR} third_party/libiconv-1.17 \
		dist/* sqlite-*

show-ports:
	@ ${DOCKER_RUN} emcc --show-ports

show-version:
	@ ${DOCKER_RUN} emcc --show-version

show-files:
	@ ${DOCKER_RUN} emcc --show-files

hooks:
	@ git config core.hooksPath githooks

image:
	@ docker-compose build

pull-image:
	@ docker-compose push

push-image:
	@ docker-compose pull

demo: docs-source/app/assets/php-web-drupal.js js

NPM_PUBLISH_DRY?=--dry-run

publish:
	npm publish ${NPM_PUBLISH_DRY}
	@ npm publish ${NPM_PUBLISH_DRY}
