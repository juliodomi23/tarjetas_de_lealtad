# Debian slim (glibc): better-sqlite3 11.10 trae prebuilt para Node 22 aqui,
# asi no hace falta compilador en la imagen. Con alpine (musl) habria que compilar.
FROM node:22-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV DB_FILE=/data/loyalty.db
EXPOSE 3000
CMD ["node", "server.js"]
