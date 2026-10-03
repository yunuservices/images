ARG BASE_IMAGE

FROM amazonlinux:2023 AS allocator-builder

COPY build/allocator-build.sh /usr/local/bin/allocator-build.sh
RUN sh /usr/local/bin/allocator-build.sh

# CI replaces this stage with prebuilt files via --build-context allocators=...
FROM scratch AS allocators
COPY --from=allocator-builder /out/ /

FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.authors="yunuservices"

COPY rootfs/ /
COPY --from=allocators /libjemalloc.so /usr/local/lib/libjemalloc.so
COPY --from=allocators --chmod=0755 /jeprof /usr/local/bin/jeprof
COPY --from=allocators /libmimalloc.so /usr/local/lib/libmimalloc.so

COPY build/runtime-setup.sh /usr/local/bin/runtime-setup.sh
RUN sh /usr/local/bin/runtime-setup.sh && rm -f /usr/local/bin/runtime-setup.sh

USER 1000:1000
ENV USER=container HOME=/home/container
WORKDIR /home/container

CMD ["/bin/sh", "/entrypoint.sh"]
