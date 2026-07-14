# Stage 1: Build Next.js standalone
FROM docker.io/library/node:20-alpine AS builder
RUN corepack enable && corepack prepare yarn@4.12.0 --activate
WORKDIR /app
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn .yarn
RUN yarn install --immutable
COPY . .
ARG NEXT_PUBLIC_BASE_URL=http://localhost
ARG NEXT_PUBLIC_DEFAULT_REGION=us
ENV NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL
ENV NEXT_PUBLIC_DEFAULT_REGION=$NEXT_PUBLIC_DEFAULT_REGION
RUN yarn build

# Stage 2: Run standalone server
FROM docker.io/library/node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
USER nextjs
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]
