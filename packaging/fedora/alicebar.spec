Name:       alicebar
Version:    1.0.0
Release:    1%{?dist}
Summary:    Flutter-based Wayland top bar for wlroots compositors
License:    GPL-3.0-only
URL:        https://github.com/garnt/alice
Source0:    %{name}-%{version}.tar.gz

# Pin this to a specific stable Flutter release:
%global flutter_version 3.27.4

BuildRequires: clang, cmake, ninja-build, pkg-config, curl, tar
BuildRequires: wayland-devel, wayland-protocols-devel, wayland-scanner
BuildRequires: gtk3-devel, gtk-layer-shell-devel
BuildRequires: atk-devel, gdk-pixbuf2-devel, harfbuzz-devel
BuildRequires: libepoxy-devel, libxkbcommon-devel, pango-devel, cairo-devel
BuildRequires: cargo, rust, dbus-devel

Requires: gtk3, gtk-layer-shell, wayland-libs, atk, gdk-pixbuf2
Requires: harfbuzz, libepoxy, libxkbcommon, pango, cairo, dbus-libs

%description
Flutter-based Wayland top bar for wlroots compositors.

%prep
%autosetup
export FLUTTER_SDK=%{_builddir}/flutter-sdk-%{flutter_version}
if [ ! -d "$FLUTTER_SDK" ]; then
  curl -Lo /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_%{flutter_version}-stable.tar.xz"
  mkdir -p "$FLUTTER_SDK"
  tar -xf /tmp/flutter.tar.xz --strip-components=1 -C "$FLUTTER_SDK"
fi
export PATH="$FLUTTER_SDK/bin:$PATH"
flutter pub get
cd native && cargo fetch && cd ..

%build
export FLUTTER_SDK=%{_builddir}/flutter-sdk-%{flutter_version}
export PATH="$FLUTTER_SDK/bin:$PATH"
export CC=clang CXX=clang++
flutter build linux --release

%install
install -d %{buildroot}/usr/lib/alicebar
cp -r build/linux/x64/release/bundle/. %{buildroot}/usr/lib/alicebar/
install -Dm755 packaging/alicebar.sh %{buildroot}/usr/bin/alicebar

%files
/usr/lib/alicebar/
/usr/bin/alicebar

%changelog
* Sun Mar 15 2026 Maintainer <maintainer@example.com> - 1.0.0-1
- Initial package
