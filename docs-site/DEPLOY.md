# Deploy Instructions — docs.synapticchain.xyz

## Step 1: Copy files to Charlie

```bash
# On Charlie (203.161.56.222)
sudo mkdir -p /var/www/docs
sudo cp -r /mnt/agents/output/docs-site/* /var/www/docs/
sudo chown -R www-data:www-data /var/www/docs
```

## Step 2: Add nginx server block

Create `/etc/nginx/sites-available/docs.synapticchain.xyz`:

```nginx
server {
    listen 80;
    server_name docs.synapticchain.xyz;
    root /var/www/docs;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
```

Enable:
```bash
sudo ln -s /etc/nginx/sites-available/docs.synapticchain.xyz /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

## Step 3: SSL with certbot

```bash
sudo certbot --nginx -d docs.synapticchain.xyz --non-interactive --agree-tos -m admin@synapticchain.xyz
```

## Step 4: Verify

```bash
curl -s -o /dev/null -w "%{http_code}" https://docs.synapticchain.xyz
# Expected: 200
```

Done. The docs site is live.
