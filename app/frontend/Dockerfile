FROM nginx:alpine

# Copy frontend files
COPY index.html /usr/share/nginx/html/
COPY nginx-frontend.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1/health || exit 1
