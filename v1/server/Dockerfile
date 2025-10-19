# FROM node:18-alpine

# WORKDIR /app

# # Copy package files
# COPY package*.json ./

# # Install dependencies
# RUN npm install --production

# # Copy application code
# COPY . .

# # Create logs directory
# RUN mkdir -p /app/logs

# # Expose port
# EXPOSE 1337

# # Start server
# CMD ["node", "index.js"]


# FROM node:18-alpine

# WORKDIR /app

# # Copy package.json
# COPY package.json ./

# # Install dependencies
# RUN npm install

# # Copy application files
# COPY index.js ./
# COPY cloud ./cloud

# # Create logs directory
# RUN mkdir -p /app/logs

# EXPOSE 1337

# CMD ["node", "index.js"]

FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application files
COPY . .

# Create logs directory
RUN mkdir -p /app/logs

EXPOSE 1337

CMD ["node", "index.js"]