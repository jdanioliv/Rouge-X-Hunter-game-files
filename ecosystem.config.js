// PM2 process config. Start everything with:
//   pm2 start ecosystem.config.js
//   pm2 save && pm2 startup   (to survive reboot - pm2 startup prints an
//                              OS-specific command to run once, as admin)
'use strict';
const path = require('path');

module.exports = {
  apps: [
    {
      name: 'agentic-os-runner',
      script: 'server/runner.js',
      cwd: __dirname,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      restart_delay: 2000,
      env: { NODE_ENV: 'production' },
      out_file: path.join(__dirname, 'output', 'pm2-runner.out.log'),
      error_file: path.join(__dirname, 'output', 'pm2-runner.err.log'),
    },
    {
      name: 'agentic-os-scheduler',
      script: 'scripts/routines/scheduler.js',
      cwd: __dirname,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      restart_delay: 5000,
      env: { NODE_ENV: 'production' },
      out_file: path.join(__dirname, 'output', 'pm2-scheduler.out.log'),
      error_file: path.join(__dirname, 'output', 'pm2-scheduler.err.log'),
    },
  ],
};
