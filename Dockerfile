# ---- Tahap 1: build aplikasi React (Vite) ----
FROM node:20-alpine AS build
WORKDIR /app

# Pasang dependensi dulu agar cache Docker efisien
COPY package*.json ./
RUN npm ci

COPY . .

# Variabel Vite ditanam saat build (bukan saat container berjalan)
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_ANON_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY

RUN npm run build

# ---- Tahap 2: sajikan hasil build dengan Nginx ----
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]