FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application source
COPY server.js ./

# Expose port 80 (matches docker-compose mapping)
EXPOSE 80

# Run as non-root user
USER node

# Start the app
CMD ["node", "server.js"]
