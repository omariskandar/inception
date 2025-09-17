#!/bin/bash
set -euo pipefail

# ----- Read env -----
DB_HOST="${DB_HOST:?}"
DB_NAME="${DB_NAME:?}"
DB_USER="${DB_USER:?}"
DB_PASS_FILE="${DB_PASSWORD_FILE:?}"

WP_TITLE="${WP_TITLE:?}"
WP_URL="${WP_URL:?}"

WP_ADMIN_USER="${WP_ADMIN_USER:?}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?}"
WP_ADMIN_PASS_FILE="${WP_ADMIN_PASSWORD_FILE:?}"

WP_USER="${WP_USER:?}"
WP_USER_EMAIL="${WP_USER_EMAIL:?}"
WP_USER_PASS_FILE="${WP_USER_PASSWORD_FILE:?}"

PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"

DB_PASS="$(cat "${DB_PASS_FILE}")"
WP_ADMIN_PASS="$(cat "${WP_ADMIN_PASS_FILE}")"
WP_USER_PASS="$(cat "${WP_USER_PASS_FILE}")"

# ----- Download WordPress if not present -----
if [ ! -f "wp-includes/version.php" ]; then
  echo "[wordpress] Downloading WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1
  chown -R nobody:nogroup /var/www/html
fi

# ----- Create wp-config.php if not exists -----
if [ ! -f "wp-config.php" ]; then
  echo "[wordpress] Creating wp-config.php..."
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
  sed -i "s/username_here/${DB_USER}/" wp-config.php
  sed -i "s/password_here/${DB_PASS}/" wp-config.php
  sed -i "s/localhost/${DB_HOST}/" wp-config.php
  # Force HTTPS behind reverse proxy
  cat >> wp-config.php <<'PHP'
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
  $_SERVER['HTTPS'] = 'on';
}
PHP
fi

# ----- Generate salts if missing -----
if ! grep -q "AUTH_KEY" wp-config.php; then
  echo "[wordpress] Adding unique salts..."
  curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php || true
fi

# ----- Try DB connectivity (finite retries, not infinite) -----
echo "[wordpress] Waiting for DB (up to ~30s)..."
for i in {1..10}; do
  if php -r '
    $h=getenv("DB_HOST"); $d=getenv("DB_NAME"); $u=getenv("DB_USER"); $p=getenv("DB_PASS");
    try { new PDO("mysql:host=$h;dbname=$d;charset=utf8mb4",$u,$p,[PDO::ATTR_TIMEOUT=>2]); exit(0);} catch(Exception $e){exit(1);}
  ' DB_HOST="${DB_HOST}" DB_NAME="${DB_NAME}" DB_USER="${DB_USER}" DB_PASS="${DB_PASS}"; then
    break
  fi
  sleep 3
done

# ----- Install site and users (idempotent) -----
if ! php -r 'require "wp-load.php"; exit(is_multisite()||get_option("siteurl")?0:1);'; then
  echo "[wordpress] Installing core..."
  php -r 'define("WP_INSTALLING", true);' || true
  php ./wp-admin/install.php >/dev/null 2>&1 || true
fi

# Ensure siteurl/home set
php -r '
require "wp-load.php";
update_option("siteurl", getenv("WP_URL"));
update_option("home", getenv("WP_URL"));
' WP_URL="${WP_URL}"

# Ensure admin user exists
php -r '
require "wp-load.php";
$u = getenv("WP_ADMIN_USER");
$e = getenv("WP_ADMIN_EMAIL");
$p = getenv("WP_ADMIN_PASS");
if (!username_exists($u)) {
  $id = wp_create_user($u,$p,$e);
  $user = new WP_User($id); $user->set_role("administrator");
} else {
  $user = get_user_by("login",$u);
  wp_update_user(["ID"=>$user->ID,"user_email"=>$e]);
}
' WP_ADMIN_USER="${WP_ADMIN_USER}" WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL}" WP_ADMIN_PASS="${WP_ADMIN_PASS}"

# Ensure regular user exists
php -r '
require "wp-load.php";
$u = getenv("WP_USER");
$e = getenv("WP_USER_EMAIL");
$p = getenv("WP_USER_PASS");
if (!username_exists($u)) {
  $id = wp_create_user($u,$p,$e);
  $user = new WP_User($id); $user->set_role("subscriber");
} else {
  $user = get_user_by("login",$u);
  wp_update_user(["ID"=>$user->ID,"user_email"=>$e]);
}
' WP_USER="${WP_USER}" WP_USER_EMAIL="${WP_USER_EMAIL}" WP_USER_PASS="${WP_USER_PASS}"

echo "[wordpress] Starting php-fpm on ${PHP_FPM_PORT}..."
exec php-fpm82 -F -R -y /etc/php82/php-fpm.conf --fpm-config /etc/php82/php-fpm.d/www.conf
