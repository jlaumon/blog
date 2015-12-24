@echo off

echo "Deleting public/"
rmdir /s /q public

echo "Regenerating public/"
hugo

echo "Git..."
git add -A
git commit -m "Updating site"

git push origin master
git subtree push --prefix=public https://github.com/jlaumon/blog.git gh-pages

pause