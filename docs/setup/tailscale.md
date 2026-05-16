## Tailscale 跨网络配置（5分钟）

### 为什么需要 Tailscale

默认情况下，iPhone 通过局域网 IP（`192.168.x.x`）连接 Mac 上的控制平面，两台设备必须在同一 WiFi 下。

Tailscale 建立一个私有 VPN 网格，让 Mac 和 iPhone 获得固定的虚拟 IP（`100.x.x.x`），无论身处何处都能互联——办公室、4G/5G、不同 WiFi 均可使用。

---

### Mac 安装步骤

```bash
brew install --cask tailscale
```

安装完成后打开 Tailscale，点击菜单栏图标，选择 **Log in**，使用 Google / GitHub 账号完成授权。

---

### iPhone 安装步骤

1. 打开 App Store，搜索 **Tailscale**，安装官方 App。
2. 打开 Tailscale App，使用**与 Mac 相同的账号**登录。
3. 允许 VPN 配置请求。

两台设备登录同一账号后，Tailscale 自动完成组网，无需额外配置。

---

### 找到 Mac 的 Tailscale IP

方式一：菜单栏

点击 Mac 菜单栏的 Tailscale 图标，当前设备的 IP 显示在顶部（格式为 `100.x.x.x`）。

方式二：终端

```bash
tailscale ip -4
```

---

### 在 iOS App 设置界面填写 Tailscale IP

1. 打开 GemmaHost，进入 **Settings**。
2. 在 Control Plane URL 输入框中填写：

   ```
   http://100.x.x.x:3000
   ```

   将 `100.x.x.x` 替换为上一步查到的 Mac Tailscale IP。

3. 点击 **Test Connection** 验证连通性，成功后点击 **Save**。

---

### 验证：运行端到端测试

在 Mac 终端执行：

```bash
bash scripts/e2e_test.sh --url http://100.x.x.x:3000
```

将 `100.x.x.x` 替换为实际 Tailscale IP。脚本会依次测试设备注册、心跳、任务提交等核心接口。

---

### 常见问题

**Q: Test Connection 失败，提示连接超时。**

- 确认 Mac 和 iPhone 的 Tailscale 均已登录（图标呈绿色连接状态）。
- 在 Mac 上运行 `tailscale status`，确认 iPhone 出现在设备列表中。
- 确认控制平面已启动：`bash scripts/start_all.sh`。

**Q: Tailscale 显示已连接，但仍无法访问。**

- macOS 防火墙可能拦截了 3000 端口。前往 **系统设置 → 网络 → 防火墙**，添加 `node` 或关闭防火墙（仅限本地开发环境）。
- 也可以临时验证：在 Mac 上运行 `curl http://100.x.x.x:3000/v1/tasks`（用 Tailscale IP 替换），确认端口可达。

**Q: 更换网络后 IP 变了吗？**

Tailscale IP（`100.x.x.x`）是固定的虚拟 IP，不随网络切换而改变，无需重新配置 App。
