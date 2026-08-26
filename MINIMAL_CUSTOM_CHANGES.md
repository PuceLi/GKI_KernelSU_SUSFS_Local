# 最小化自定义功能修改总结

## 📋 修改内容

本分支 `minimal-custom` 基于原始仓库 (commit `bd6cab1`)，只添加了两个核心功能：

### ✅ 1. 自定义 SUSFS 仓库支持

**目的**：允许用户使用自己的 SUSFS 仓库和分支，而不是默认的官方仓库。

**修改文件**：
- `.github/workflows/build.yml` - 添加输入参数和克隆逻辑
- `.github/workflows/kernel-a12-5-10.yml` - 添加参数传递
- `.github/workflows/kernel-a13-5-15.yml` - 添加参数传递
- `.github/workflows/kernel-a14-6-1.yml` - 添加参数传递
- `.github/workflows/kernel-a15-6-6.yml` - 添加参数传递
- `.github/workflows/kernel-a16-6-12.yml` - 添加参数传递

**新增参数**：
- `susfs_repo_url`: 自定义 SUSFS 仓库地址（留空使用默认）
- `susfs_commit_id`: 自定义 SUSFS 提交 ID/分支/标签（留空使用默认分支）

**使用示例**：
```
自定义 SUSFS 仓库地址: https://github.com/PuceLi/susfs4ksu
自定义 SUSFS 提交 ID/分支/标签: gki-android14-6.1-fixed
```

### ✅ 2. CONFIG_USER_NS 配置优化

**目的**：为所有启用 Droidspaces 的版本启用 `CONFIG_USER_NS`，而不仅仅是 Android 15。

**修改文件**：
- `.github/workflows/build.yml` - Droidspaces 配置部分

**修改内容**：
- 将 `CONFIG_USER_NS=y` 从 Android 15 专属配置移到所有 Droidspaces 通用配置
- 保留 Android 15 + 6.6 的特殊配置（禁用 `CONFIG_ANDROID_PARANOID_NETWORK`）

## 📊 对比原仓库

```bash
 .github/workflows/build.yml           | 44 +++++++++++++++++++++++++++++++----
 .github/workflows/kernel-a12-5-10.yml | 12 ++++++++++
 .github/workflows/kernel-a13-5-15.yml | 12 ++++++++++
 .github/workflows/kernel-a14-6-1.yml  | 12 ++++++++++
 .github/workflows/kernel-a15-6-6.yml  | 12 ++++++++++
 .github/workflows/kernel-a16-6-12.yml | 12 ++++++++++
 6 files changed, 100 insertions(+), 4 deletions(-)
```

**只修改了工作流文件，没有修改任何核心构建脚本（如 `scripts/susfs_fixes/apply.sh`）。**

## 🎯 使用方法

### 方法 1：使用默认配置（与原仓库相同）
直接触发工作流，不填写自定义 SUSFS 参数，行为与原仓库完全一致。

### 方法 2：使用自定义 SUSFS
在触发工作流时填写：
1. **自定义 SUSFS 仓库地址**：你的 fork 地址
2. **自定义 SUSFS 提交 ID/分支/标签**：你的自定义分支名

## ✅ 兼容性

- ✅ 完全兼容原仓库的所有功能
- ✅ 不填写自定义参数时行为与原仓库一致
- ✅ 不影响其他 KernelSU 变体（Official、Next、ReSukiSU 等）
- ✅ 所有原有的配置选项都保持不变

## 🔄 如何切换分支

### 切换到干净的最小化自定义分支
```bash
git checkout minimal-custom
```

### 切换回你的开发分支
```bash
git checkout dev
```

### 推送这个分支到 GitHub
```bash
git push origin minimal-custom
```

## 📝 提交历史

```
a2efaf6 feat: 添加自定义 SUSFS 仓库和 USER_NS 配置
bd6cab1 chore: update GKI kernel version data (原仓库)
```

只有 1 个自定义提交，非常干净！
