@echo off

echo "Deleting public/"
rmdir /s /q public

echo "Copying CNAME"
mkdir public
cp CNAME public

echo "Generating content"
hugo

echo "Git..."
git add -A
git commit -m "Updating site"

git push origin master
git subtree push --prefix=public https://github.com/jlaumon/blog.git gh-pages

pause