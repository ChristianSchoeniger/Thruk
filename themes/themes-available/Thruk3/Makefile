
build: fonts node_modules
	mkdir -p stylesheets
	NODE_ENV=production \
		npx tailwindcss -o stylesheets/Thruk3.css --input ./src/Thruk3.css --postcss ./postcss.config.js

dev: fonts node_modules
	mkdir -p stylesheets
	NODE_ENV=dev \
		npx tailwindcss -o stylesheets/Thruk3.css --input ./src/Thruk3.css --postcss ./postcss.config.js

watch: fonts node_modules
	mkdir -p stylesheets
	NODE_ENV=dev \
		npx tailwindcss -o stylesheets/Thruk3.css --input ./src/Thruk3.css --postcss ./postcss.config.js --watch

node_modules:
	npm i -D \
		tailwindcss@latest \
		postcss@latest \
		autoprefixer@latest \
		postcss-nested@latest \
		postcss-import@latest \

	npm install --save @iconscout/unicons

fonts: node_modules
	rm -rf fonts
	cp -rp ./node_modules/@iconscout/unicons/fonts .

clean:
	rm -rf \
		node_modules \
		fonts \
		package.json \
		package-lock.json \
		stylesheets \

