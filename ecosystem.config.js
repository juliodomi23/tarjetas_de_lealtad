module.exports = {
  apps: [{
    name: 'lealtad',
    script: 'server.js',
    env: {
      PORT: 3001,
      DB_FILE: '/var/data/lealtad/loyalty.db',
      // Super-admin para crear nuevos negocios via POST /api/businesses
      SUPER_PASS: 'super-cambiar',
      // Slug del negocio por defecto que se siembra al iniciar
      DEFAULT_SLUG: 'negocio-1',
      // Config del negocio por defecto (solo aplica en el primer inicio)
      BUSINESS_NAME: 'Mi Negocio',
      PRIMARY_COLOR: '#E23B3B',
      LOGO_URL: '',
      CYCLE_DAYS: 30,
      ADMIN_PASS: 'cambiar',
    },
  }],
};
