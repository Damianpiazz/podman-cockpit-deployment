# ---------------------------------------------------------------
# Vercel Commerce – multi-stage Docker build
# ---------------------------------------------------------------
FROM docker.io/library/node:20-alpine AS base
RUN corepack enable && corepack prepare pnpm@latest --activate

# ---- Dependencies ----
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# ---- Build ----
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NEXT_PUBLIC_BASE_URL=http://localhost
ENV NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL

ARG SHOPIFY_STORE_DOMAIN="placeholder.myshopify.com"
ARG SHOPIFY_STOREFRONT_ACCESS_TOKEN=""
ARG SHOPIFY_REVALIDATION_SECRET=""
ARG COMPANY_NAME="Vercel Inc."
ARG SITE_NAME="Next.js Commerce"

ENV SHOPIFY_STORE_DOMAIN=$SHOPIFY_STORE_DOMAIN
ENV SHOPIFY_STOREFRONT_ACCESS_TOKEN=$SHOPIFY_STOREFRONT_ACCESS_TOKEN
ENV SHOPIFY_REVALIDATION_SECRET=$SHOPIFY_REVALIDATION_SECRET
ENV COMPANY_NAME=$COMPANY_NAME
ENV SITE_NAME=$SITE_NAME

RUN pnpm build

# ---- Production ----
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
