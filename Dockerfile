# Rebuild the source code only when needed
FROM registry.access.redhat.com/ubi8/nodejs-14-minimal AS builder_web
ARG DEVFILE_VIEWER_ROOT
ARG DEVFILE_COMMUNITY_HOST
USER root
WORKDIR /app
RUN npm install -g yarn
COPY ./app/ .
RUN $(npm get prefix)/bin/yarn install --frozen-lockfile --ignore-optional
RUN $(npm get prefix)/bin/yarn build
RUN $(npm get prefix)/bin/yarn install --production --ignore-scripts --prefer-offline --ignore-optional


FROM quay.io/openshift-pipeline/golang:1.15-alpine AS builder_devfile
RUN apk add --no-cache git bash curl zip

# Install yq
RUN curl -sL -O https://github.com/mikefarah/yq/releases/download/v4.9.5/yq_linux_amd64 -o /usr/local/bin/yq && mv ./yq_linux_amd64 /usr/local/bin/yq && chmod +x /usr/local/bin/yq

COPY ./registry/ /registry
COPY ./registry-support/ /registry-support

# Run the registry build tools
RUN /registry-support/build-tools/build.sh /registry /build
RUN chown -R 1001:0 /registry
RUN chown -R 1001:0 /build



# Production image, copy all the files and run next
FROM registry.access.redhat.com/ubi8/nodejs-14-minimal AS runner
USER root
WORKDIR /app
RUN microdnf install shadow-utils

ENV NODE_ENV production

RUN groupadd -g 1001 nodejs
RUN useradd nextjs -u 1001

COPY --from=builder_web /app/next.config.js ./
COPY --from=builder_web /app/public ./public
COPY --from=builder_web /app/.next ./.next
COPY --from=builder_web /app/node_modules ./node_modules
COPY --from=builder_web /app/package.json ./package.json
COPY --from=builder_web /app/config ./config
COPY --from=builder_web /app/webpage_info ./webpage_info

COPY --from=builder_devfile /build /registry

RUN chown -R 1001:0 .

USER nextjs

EXPOSE 3000

CMD ["npm", "start"]
