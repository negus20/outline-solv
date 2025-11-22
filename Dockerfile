# ---- BUILD STAGE ----
ARG APP_PATH=/opt/outline
FROM node:20-slim AS build

# Set working directory inside the container
ARG APP_PATH
WORKDIR $APP_PATH

# Install system dependencies needed to build native modules
RUN apt-get update && apt-get install -y \
  python3 \
  make \
  g++ \
  && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests
COPY package.json yarn.lock ./

# Install dependencies
RUN yarn install --frozen-lockfile

# Copy the rest of the repo (your forked Outline code, including public/index.html)
COPY . .

# Build Outline (creates ./build, ./public, ./server, etc.)
RUN yarn build


# ---- RUNTIME STAGE ----
FROM node:20-slim AS runner

LABEL org.opencontainers.image.source="https://github.com/outline/outline"

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH
ENV NODE_ENV=production

# Create a non-root user compatible with Debian and BusyBox based images
RUN addgroup --gid 1001 nodejs && \
    adduser --uid 1001 --ingroup nodejs nodejs && \
    mkdir -p /var/lib/outline && \
    chown -R nodejs:nodejs /var/lib/outline

# Copy built app from the build stage
COPY --from=build --chown=nodejs:nodejs $APP_PATH/build ./build
COPY --from=build $APP_PATH/server ./server
COPY --from=build $APP_PATH/public ./public
COPY --from=build $APP_PATH/.sequelizerc ./.sequelizerc
COPY --from=build $APP_PATH/node_modules ./node_modules
COPY --from=build $APP_PATH/package.json ./package.json

# Install wget to healthcheck the server
RUN apt-get update \
    && apt-get install -y wget \
    && rm -rf /var/lib/apt/lists/*

# Local file storage dir (if you're not using S3)
ENV FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data
RUN mkdir -p "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chown -R nodejs:nodejs "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chmod 1777 "$FILE_STORAGE_LOCAL_ROOT_DIR"

USER nodejs

HEALTHCHECK --interval=1m CMD wget -qO- "http://localhost:${PORT:-3000}/_health" | grep -q "OK" || exit 1

EXPOSE 3000
CMD ["yarn", "start"]
