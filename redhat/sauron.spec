Summary: Sauron - DNS/DHCP management system
Name: sauron
Version: 0.7.3
Release: 1
URL: http://sauron.jyu.fi/
License: GPL
Group: Applications/Internet
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-buildroot
BuildRequires: perl >= 0:5.004
Requires: perl >= 0:5.004
# Requires: postgresql-perl
# Requires: perl-Net-Netmask
BuildArch: noarch

%description
Sauron is a scalable system for management of DNS & DHCP services. Sauron
can manage multiple DNS/DHCP servers and dynamically generates complete
DNS/DHCP configuration from a central SQL-database (PostgreSQL). 
Sauron has www interface and command-line interface.

%prep
if [ "${RPM_BUILD_ROOT}x" == "x" ]; then
        echo "RPM_BUILD_ROOT empty, bad idea!"
        exit 1
fi
if [ "${RPM_BUILD_ROOT}" == "/" ]; then
        echo "RPM_BUILD_ROOT is set to "/", bad idea!"
        exit 1
fi
%setup -q

%build
./configure --prefix=/opt --sysconfdir=/etc
make

%install
rm -rf $RPM_BUILD_ROOT
make install INSTALL_ROOT=$RPM_BUILD_ROOT

install -d -m 755 $RPM_BUILD_ROOT/var/www
install -d -m 751 $RPM_BUILD_ROOT/var/www/cgi-bin
install -d -m 751 $RPM_BUILD_ROOT/var/www/html/sauron/icons
ln -s /opt/sauron/cgi/sauron.cgi $RPM_BUILD_ROOT/var/www/cgi-bin/sauron.cgi
ln -s /opt/sauron/cgi/browser.cgi $RPM_BUILD_ROOT/var/www/cgi-bin/browser.cgi
ln -s /opt/sauron/icons/logo_large.png $RPM_BUILD_ROOT/var/www/html/sauron/icons/logo_large.png
ln -s /opt/sauron/icons/logo.png $RPM_BUILD_ROOT/var/www/html/sauron/icons/logo.png

install -d -m 755 $RPM_BUILD_ROOT/usr/share/man/man1
install -m 644 -c doc/sauron.1 $RPM_BUILD_ROOT/usr/share/man/man1

mv $RPM_BUILD_ROOT/opt/sauron/Sauron/DB-Pg.pm{,.notinuse}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
/opt/sauron/*
/etc/sauron/config.in
/etc/sauron/config-browser.in
/var/www/cgi-bin/*
/var/www/html/sauron
/usr/share/man/man1/*
%config /etc/sauron/config
%config /etc/sauron/config-browser
%doc README README.upgrade COPYRIGHT ChangeLog
%doc test
%doc doc/manual.pdf
%doc doc/tables.html
# %doc doc/manual


%changelog
* Thu Feb 28 2008 Timo Kokkone <tjko@iki.fi> - 0.7.3-1
- version bumbed to 0.7.3

* Sun May 15 2005 Timo Kokkone <tjko@iki.fi> - 0.7.2-1
- version bumbed to 0.7.2

* Wed Dec 31 2003 Timo Kokkonen <tjko@iki.fi> - 0.7.1-1
- hack to avoid Pg module dependency

* Wed Mar  5 2003 Timo Kokkonen <tjko@iki.fi> 0.6.0-1
- added manual page & manual

* Tue Jan 21 2003 Timo Kokkonen <tjko@iki.fi> 0.5.1-2
- relaxed perl requirements

* Thu Jan  9 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-5
- fixed broken symlinks & some directory permissions

* Thu Jan  9 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-4
- now installs symlinks under /var/www

* Wed Jan  8 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-3
- included more docs

* Mon Jan  6 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-2
- included test directory in docs

* Tue Nov 26 2002 Timo Kokkonen <tjko@cc.jyu.fi>
- Initial build.


