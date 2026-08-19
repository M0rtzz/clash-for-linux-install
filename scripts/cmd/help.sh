#!/usr/bin/env bash

clashhelp() {
  cat <<EOF

Usage:
  clashctl COMMAND [OPTIONS]

Commands:
  on                    开启代理
  off                   关闭代理
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  node                  节点切换
  tun                   Tun 模式（system 安装禁用）
  mixin                 Mixin 配置
  secret                Web 密钥
  log                   查看日志
  init                  初始化当前用户
  env                   输出代理环境变量
  doctor                查看当前用户诊断信息
  migrate               迁移旧版用户数据
  uninit                清理当前用户数据
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

For more help on how to use clashctl, head to https://github.com/nelvko/clash-for-linux-install
EOF
}
