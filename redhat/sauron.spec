Summary: Sauron - DNS/DHCP management system
Name: sauron
Version: 0.5.0
Release: 1
URL: http://sauron.jyu.fi/
Source0: %{name}-%{version}.tar.gz
License: GPL
Group: Applications/Internet
BuildRoot: %{_tmppath}/%{name}-%{version}-buildroot
BuildRequires: perl >= 5.6.0
Requires: perl >= 5.6.0, perl-CGI, postgresql-perl, perl-Digest-HMAC
Requires: perl-Net-Netmask
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
%doc README COPYRIGHT COPYING ChangeLog

%changelog
* Tue Nov 26 2002 Timo Kokkonen <tjko@cc.jyu.fi>
- Initial build.


