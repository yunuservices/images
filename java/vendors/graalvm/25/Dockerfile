FROM container-registry.oracle.com/graalvm/jdk:25 AS allocator-builder

COPY build/allocator-build.sh /usr/local/bin/allocator-build.sh
RUN sh /usr/local/bin/allocator-build.sh

FROM container-registry.oracle.com/graalvm/jdk:25
LABEL org.opencontainers.image.authors="yunuservices"

COPY ./entrypoint.sh /entrypoint.sh
COPY --from=allocator-builder /out/libjemalloc.so /usr/local/lib/libjemalloc.so
COPY --from=allocator-builder /out/jeprof /usr/local/bin/jeprof
COPY --from=allocator-builder /out/libmimalloc.so /usr/local/lib/libmimalloc.so

COPY build/runtime-setup.sh /usr/local/bin/runtime-setup.sh
RUN sh /usr/local/bin/runtime-setup.sh && rm -f /usr/local/bin/runtime-setup.sh

USER 1000:1000
ENV USER=container HOME=/home/container
WORKDIR /home/container

CMD ["/bin/sh", "/entrypoint.sh"]