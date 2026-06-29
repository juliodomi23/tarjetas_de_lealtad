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

## Por cliente nuevo

Cada negocio es una instancia separada. Copia el directorio, cambia el puerto y las variables en `ecosystem.config.js`, y agrega un nuevo bloque en nginx.
