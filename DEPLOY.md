# Deploy en VPS

## 1. Subir archivos al VPS

```bash
scp -r . usuario@tu-vps:/var/www/lealtad
```

O clona desde git si ya tienes el repo.

## 2. Instalar dependencias

```bash
cd /var/www/lealtad
npm install --production
```

## 3. Crear carpeta de datos

```bash
mkdir -p /var/data/lealtad
```

## 4. Instalar PM2 (si no está)

```bash
npm install -g pm2
```

## 5. Levantar con PM2

Edita `ecosystem.config.js` con los valores reales del negocio, luego:

```bash
pm2 start ecosystem.config.js
pm2 save
pm2 startup   # para que arranque al reiniciar el VPS
```

## 6. Configurar nginx

```bash
sudo cp nginx.conf /etc/nginx/sites-available/lealtad
sudo ln -s /etc/nginx/sites-available/lealtad /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## 7. SSL con Certbot

```bash
sudo certbot --nginx -d lealtad.ambarrojo.com
```

## 8. Apuntar el dominio

En el panel de Hostinger, agrega un registro A:
- Nombre: `lealtad`
- Valor: IP del VPS

---

## Respaldo diario de la base de datos

Usa el script versionado `backup.sh` (ajusta rutas con `DB_FILE`/`BACKUP_DIR` si difieren):

```bash
sudo apt install -y sqlite3
chmod +x /var/www/lealtad/backup.sh
crontab -e
```

Agrega esta línea (diario a las 4 AM, conserva 30 días):

```
0 4 * * * DB_FILE=/var/www/lealtad/loyalty.db BACKUP_DIR=/var/backups/lealtad /var/www/lealtad/backup.sh >> /var/log/lealtad-backup.log 2>&1
```

Verifica que corrió: `ls /var/backups/lealtad` al día siguiente.

---

## Aviso por WhatsApp/n8n al ganar premio (opcional)

Define `WEBHOOK_URL` en el entorno (ecosystem.config.js o EasyPanel). Cuando un
cliente gana premio, el server hace `POST` a esa URL con:

```json
{ "event": "reward_earned", "business": "...", "slug": "...", "name": "...",
  "phone": "...", "earned": ["Corte gratis"], "pending_rewards": 1 }
```

En n8n: un Webhook node que reciba esto y mande el WhatsApp.

---

## Por cliente nuevo

El sistema es multi-tenant: da de alta el negocio desde `/superadmin.html` (o
`POST /api/businesses` con `SUPER_PASS`). No hace falta otra instancia.
