module.exports = {
  apps: [{
    name: 'lealtad',
    script: 'server.js',
    env: {
      PORT: 3001,
      BUSINESS_NAME: 'Mi Negocio',
      GOAL: 8,
      REWARD_TEXT: 'Premio gratis',
      ADMIN_PASS: 'cambiar',
      PRIMARY_COLOR: '#E23B3B',
      LOGO_URL: '',
      DB_FILE: '/var/data/lealtad/loyalty.db',
    },
  }],
};
