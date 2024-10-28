FROM quay.io/toolbx/arch-toolbox AS arch-distrobox

COPY pkgs.yml /tmp/
COPY mirrorlist /etc/pacman.d/
RUN sed -i 's/#Color/Color/g' /etc/pacman.conf && \
    printf "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" | tee -a /etc/pacman.conf && \
    sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g' /etc/makepkg.conf && \
    pacman-key --init && pacman-key --populate && \
    pacman -Syu --noconfirm && \
    useradd -m --shell=/bin/bash build && usermod -L build && \
    echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    pacman -S --clean --clean

# Distrobox Integration
RUN git clone https://github.com/89luca89/distrobox.git --single-branch --depth 1 /tmp/distrobox && \
    cp /tmp/distrobox/distrobox-host-exec /usr/bin/distrobox-host-exec && \
    wget https://github.com/1player/host-spawn/releases/download/$(cat /tmp/distrobox/distrobox-host-exec | grep host_spawn_version= | cut -d "\"" -f 2)/host-spawn-$(uname -m) -O /usr/bin/host-spawn && \
    chmod +x /usr/bin/host-spawn && \
    rm -drf /tmp/distrobox

# SystemD Integration
RUN ln -s /run/host/run/systemd/system /run/systemd && \
    mkdir -p /run/dbus && \
    ln -s /run/host/run/dbus/system_bus_socket /run/dbus

# Add paru and install AUR packages
USER build
WORKDIR /home/build
RUN git clone https://aur.archlinux.org/paru-bin.git --single-branch --depth 1 && \
    cd paru-bin && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -drf paru-bin

RUN paru -S aur/whyq-bin extra/jq --noconfirm --needed

RUN whyq -r '.aur.[]?' /tmp/pkgs.yml \
    | xargs -r paru -S --noconfirm --needed

USER root
WORKDIR /

RUN whyq -r '.arch_distrobox.[]?' /tmp/pkgs.yml \
    | xargs -r pacman -S --noconfirm --needed \
    && rm -rf /var/cache/pacman/pkg/*

RUN whyq -r '.arch.[]?' /tmp/pkgs.yml \
    | xargs -r pacman -S --noconfirm --needed \
    && rm -rf /var/cache/pacman/pkg/*

RUN for exe in $(whyq -r '.host_exec.[]?' /tmp/pkgs.yml); do \
    ln -s /usr/bin/distrobox-host-exec /usr/local/bin/"$exe"; \
done

# Cleanup
RUN sed -i 's@#en_AU.UTF-8@en_AU.UTF-8@g' /etc/locale.gen && \
    userdel -r build && \
    rm -drf /home/build && \
    sed -i '/build ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    sed -i '/root ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    rm -rf /tmp/*
