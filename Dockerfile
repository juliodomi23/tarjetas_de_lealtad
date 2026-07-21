# Debian slim (glibc): better-sqlite3 11.10 trae prebuilt para Node 22 aqui,
# asi no hace falta compilador en la imagen. Con alpine (musl) habria que compilar.
FROM node:22-slim
# tzdata para que 'localtime' de SQLite use la hora de Tuxtla. El almacenamiento
# es UTC a propósito (ver db.js); TZ solo afecta a la métrica "nuevos hoy".
RUN apt-get update && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*
ENV TZ=America/Mexico_City
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV DB_FILE=/data/loyalty.db
EXPOSE 3000
CMD ["node", "server.js"]
