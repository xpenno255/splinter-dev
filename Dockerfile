# Splinter — static site served by nginx
# Built and pushed to ghcr.io by .github/workflows/deploy.yml,
# then run on Azure Container Apps (see azure-setup.sh).
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Site files (what .dockerignore doesn't exclude); nginx.conf must stay in the
# build context for the COPY above, so drop the stray copy from the web root
COPY . /usr/share/nginx/html
RUN rm /usr/share/nginx/html/nginx.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -q --spider http://localhost/ || exit 1
