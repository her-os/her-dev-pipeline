# 发邀请码

位置：`her-web/src/scripts/batch-send-invite-codes.ts`

## 单人快速发码（最常用）

```bash
# 工作目录：her-web 仓库根目录
cd /Users/suyuan/Documents/her-source/her-web

# 1. 创建单行 CSV（微信号可留空）
python3 -c "
import csv, io, sys
buf = io.StringIO()
w = csv.writer(buf)
w.writerow(['email', 'name', 'wechat'])
w.writerow(['user@example.com', '称呼', '微信号或留空'])
sys.stdout.write(buf.getvalue())
" > /tmp/invite-single.csv

# 2. 开 SSH 隧道连生产库
/usr/bin/ssh -f -N -L 15432:172.17.255.75:5432 ubuntu@192.144.187.174

# 3. Resend 配置从生产库 config 表获取：
#    SELECT name, value FROM config WHERE name IN ('resend_api_key', 'resend_email_from');
#    当前值：
#      resend_api_key    = re_jL1i5Vjp_Bybj2G67tXTSCM5xcSeozvrT
#      resend_email_from = Her <no-reply@mail.hersoul.cn>

# 4. 发码（先 dry-run 确认再去掉 --dry-run）
DATABASE_URL='postgresql://her:HerAgent%232026@127.0.0.1:15432/her_web' \
DATABASE_PROVIDER=postgres \
RESEND_API_KEY='re_jL1i5Vjp_Bybj2G67tXTSCM5xcSeozvrT' \
RESEND_EMAIL_FROM='Her <no-reply@mail.hersoul.cn>' \
npx tsx src/scripts/batch-send-invite-codes.ts \
  --csv /tmp/invite-single.csv \
  --batch '单独发码' \
  --balance 100 \
  --expires-at 2026-07-01 \
  --dry-run

# 5. 清理
kill $(lsof -ti :15432) 2>/dev/null
rm /tmp/invite-single.csv
```

**要点**：
- 本地 .env.local 的 DATABASE_URL 指向 local-prod-snapshot（54330），**没有 metadata 列**，发码必须走生产库
- 命令行显式传 DATABASE_URL 会覆盖 .env.local，不用改文件
- 邮件失败不影响码的创建，可以用 `/api/admin/invite-codes/send` 补发

## 批量发码（CSV）

**`--balance` 和 `--expires-at` 是必填参数，发码前必须向用户确认额度和过期日期。**

```bash
# 基本用法（必须指定额度和过期日期）
npx tsx src/scripts/batch-send-invite-codes.ts \
  --csv applicants.csv \
  --batch '百人内测-第三组' \
  --balance 100 \
  --expires-at 2026-07-01

# 自定义参数
npx tsx src/scripts/batch-send-invite-codes.ts \
  --csv applicants.csv \
  --batch '百人内测-第三组' \
  --tier max \
  --trial-days 15 \
  --balance 2000 \
  --expires-at 2026-07-01

# 先 dry-run 检查
npx tsx src/scripts/batch-send-invite-codes.ts \
  --csv applicants.csv \
  --batch '百人内测-第三组' \
  --balance 100 \
  --expires-at 2026-07-01 \
  --dry-run
```

## 环境变量

通过 SSH 隧道连生产库（见上方单人发码步骤）或本地 .env.local：
- `DATABASE_URL` — 数据库连接（**必须是生产库**，local-prod 缺 metadata 列）
- `DATABASE_PROVIDER=postgres`
- `RESEND_API_KEY` — Resend API 密钥（从生产库 config 表获取）
- `RESEND_EMAIL_FROM` — 发件人（如 `Her <no-reply@mail.hersoul.cn>`）

CSV 自动识别中英文表头：邮箱/email、称呼/姓名/name、微信号/wechat。

脚本行为：
- `note` 存人读备注（如 `百人内测-第三组-夙愿`），admin 后台显示
- `metadata` 存 JSON（wechat/name），用户兑换邀请码时自动回写微信号和真实姓名
- 邮件使用 Her 品牌模板（React Email），主题：从这里开始，与Her相遇
