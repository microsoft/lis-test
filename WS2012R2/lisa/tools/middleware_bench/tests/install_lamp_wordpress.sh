#!/bin/bash

logger "Installing LAMP + WordPress"
distro="$(head -1 /etc/issue)"

git clone https://github.com/WordPress/WordPress
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp


if [[ ${distro} == *"Ubuntu"* ]]
then
	sudo apt-get -y update
	# Install the LAMP stack
	# Set up a silent install of MySQL
	sudo bash -c 'export DEBIAN_FRONTEND=noninteractive;apt-get install -y mysql-server'
	if [ $? -ne 0 ]; then
		echo -e "Failed to install mysql,please check installation logs"
		exit 1
	fi
	sudo apt-get -y install apache2 php libapache2-mod-php php-mcrypt php-mysql php-gd
	if [ $? -ne 0 ]; then
		echo -e "Failed to install package,please check installation logs"
		exit 1
	fi
	
	# Create a MySQL Database and User for WordPress
	sudo mysql -u root -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
	sudo mysql -u root -e "GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'p@ssw0rd0507';"
	sudo mysql -u root -e "FLUSH PRIVILEGES;"


	#Adjust Apache's Configuration to Allow for .htaccess Overrides and Rewrites
	sudo sed -i '1,$d' /etc/apache2/mods-enabled/dir.conf
	echo | sudo tee /etc/apache2/mods-enabled/dir.conf << EOF
<IfModule mod_dir.c>
    DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm
</IfModule>
EOF

	echo | sudo tee -a /etc/apache2/apache2.conf << EOF
<Directory /var/www/html/>
    AllowOverride All
</Directory>
EOF

	#enable mod_rewrite so that we can utilize the WordPress permalink feature
	sudo a2enmod rewrite

	#Download and configure wordpress
	sudo cp -a WordPress/. /var/www/html

	sudo wp core config --dbhost=127.0.0.1 --dbname=wordpress --dbuser=wordpressuser --dbpass=p@ssw0rd0507 --allow-root --path='/var/www/html' 
	sudo wp core install --url=http://$1 --title="My Test WordPress" --admin_name=wordpress_admin --admin_password='4Long&Strong1' --admin_email=you@example.com --allow-root --path='/var/www/html' 

	# Restart Apache
	sudo systemctl stop apache2
	sleep 30
	sudo systemctl start apache2
	sleep 30


elif [[ ${distro} == *"Amazon"* ]]
then
	sudo yum -y install mysql-server apache2 php libapache2-mod-php php-mcrypt php-mysql php-gd
	sudo service mysqld start
	# Create a MySQL Database and User for WordPress
	sudo mysql -u root -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
	sudo mysql -u root -e "GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'p@ssw0rd0507';"
	sudo mysql -u root -e "FLUSH PRIVILEGES;"

	sudo cp -a WordPress/. /var/www/html
	wp core config --dbhost=127.0.0.1 --dbname=wordpress --dbuser=wordpressuser --dbpass=p@ssw0rd0507 --allow-root --path='/var/www/html' 
	wp core install --url=http://$1 --title="My Test WordPress" --admin_name=wordpress_admin --admin_password='4Long&Strong1' --admin_email=you@example.com --allow-root --path='/var/www/html' 

	# Restart Apache
	sudo service httpd stop
	sleep 30
	sudo service httpd start
	sleep 30
fi


echo "PHP Version: `php -v`"
echo "MySQL Version: `mysql -V`"
wget --spider -q -o /dev/null  --tries=1 -T 5 http://$1/?p=1
if [ $? -eq 0 ]; then
    echo -e "http://$1/?p=1 is reachable!"
else
    echo -e "Error: http://$1/?p=1 is unreachable!"
    exit 1
fi
