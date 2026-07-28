## 當第一次使用專案
1. 複製專案到本機：git clone https://github.com/HYZ940411/Alchemy-Workout.git
2. 創建分支（請改自己的學號）：git checkout -b "學號"

## 以後每一次使用時
1. 先看自己在哪條分支：git branch
2. 切換到 main：git checkout main
3. 再跟 main 同步新資料：git pull origin main
4. 切換回自己的分支（請改自己的學號）：git checkout "學號"
5. 把最新的 main 內容合併進自己的分支：git merge main
6. 改完檔案後：git add .
7. Commit：git commit -m "新增/修改/刪除：說明這次改了什麼"
8. Push：git push origin "學號"
9. Push 完後回瀏覽器開 Pull Request