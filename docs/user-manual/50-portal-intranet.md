# Portal 内网部署

ZotPrime Portal 是基于 Next.js 的网页门户,部署在内网环境,监听 `http://SERVER_IP:3045/`。本章节描述其部署、访问流程与运维要点。

## 访问方式

浏览器访问:

```
http://<SERVER_IP>:3045/
```

内网仅需 HTTP,无需 HTTPS(由反向代理或客户端到服务器的可信网络保证)。

## 环境变量

`.env` 中至少包含以下三项:

```bash
PORTAL_SESSION_SECRET=<至少 32 字符的随机字符串>   # iron-session 加密密钥
API_SUPER_TOKEN=<与 dataserver 的 API_SUPER_TOKEN 一致>
SECURE_COOKIES=false                                  # HTTP 内网必须
```

`SECURE_COOKIES=false` 是关键:默认值为 `true`,会让 iron-session 在 HTTP 环境下不下发 cookie,导致登录永远失败。

## 启动

Portal service 在 `docker-compose.yml` 中位于 `profiles: ["portal"]` 分组,需要显式指定:

```bash
docker compose --profile portal up -d zotprime-portal
docker compose --profile portal ps zotprime-portal
```

## 登录流程(无 2FA)

Portal 当前已移除二维码 Authenticator 二因素验证。

- **注册**:访问 `/register`,填写 username / email / password / confirm password → 提交后**直接进入 `/portal`**
- **登录**:访问 `/login`,填写 username / password → 提交后**直接进入 `/portal`**
- **注销**:在 `/portal` 页面右上角点 "Logout" → 回到 `/`

rate limiting 由 `stack/webui/portal/config.yaml` 的 `security.rate_limit` 段控制,5 次/分钟的认证失败将触发限流。

## 旧部署清理

如果升级前的版本曾启用 2FA,容器内可能残留 `stack/webui/portal/data/db.json` 文件:

```bash
# 在 portal 容器内,或在宿主机 (如果 data/ 挂载) 删除:
rm -f /app/data/db.json
```

新版 Portal 不再读写该文件,删除只是回收磁盘。**不影响已经注册的用户**——用户记录在 dataserver 里,与 Portal 无关。

## 故障排查

| 现象 | 原因 | 处置 |
|---|---|---|
| 登录后立刻被踢回登录页 | `SECURE_COOKIES=true` 在 HTTP 下不发 cookie | `.env` 改为 `SECURE_COOKIES=false` + 重启 |
| 登录成功却空白页 | dataserver 未启动 / API token 不一致 | `docker compose logs zotprime-dataserver` |
| `/portal/item/:id` 404 | 该 item 不在登录用户可见的 group 中 | 联系管理员调整 group 成员 |
| 注册报 "user already exists" | username 在 dataserver 中已被占用 | 换一个 username |