Summary: Sauron - DNS/DHCP management system
Name: sauron
Version: 0.5.0
Release: 3
URL: http://sauron.jyu.fi/
Packager: Timo Kokkonen <tjko@iki.fi>
License: GPL
Group: Applications/Internet
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-buildroot
BuildRequires: perl >= 5.6.0
Requires: perl >= 5.6.0, perl-CGI, postgresql-perl
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

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
/opt/sauron/*
/etc/sauron/config.in
/etc/sauron/config-browser.in
%config /etc/sauron/config
%config /etc/sauron/config-browser
%doc README COPYRIGHT ChangeLog
%doc test
%doc doc

%changelog
* Wed Jan  8 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-3
- included more docs

* Mon Jan  6 2003 Timo Kokkonen <tjko@iki.fi> 0.5.0-2
- included test directory in docs

* Tue Nov 26 2002 Timo Kokkonen <tjko@cc.jyu.fi>
- Initial build.


