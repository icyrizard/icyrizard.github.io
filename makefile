build:
	JEKYLL_ENV=production bundle exec jekyll build

deploy:
	(cd _icyrizard-blog/ && git add . && git commit -m "Blog update" && git push origin master)

serve:
	bundle exec jekyll serve
