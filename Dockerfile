# Splinter — static site served by nginx
# Built and pushed to ghcr.io by .github/workflows/deploy.yml,
# then run on Azure Container Apps (see azure-setup.sh).
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Site files (what .dockerignore doesn't exclude)
COPY . /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://localhost/ || exit 1
