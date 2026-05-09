module.exports = {
  apps: [{
    name: 'synaptic-gateway',
    script: './server.js',
    instances: 1,
    exec_mode: 'fork',
    env: { NODE_ENV: 'production', PORT: 8080 },
    log_file: './logs/gateway.log',
    merge_logs: true,
    time: true
  }]
};
