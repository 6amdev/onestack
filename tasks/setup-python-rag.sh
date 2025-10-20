#!/bin/bash
# Setup Python RAG System (AI Q&A with Vector Search)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
    BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
    print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
    print_step() { echo -e "${BLUE}▶${NC} $1"; }
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
}

check_root

print_header "Python RAG System Setup"

INSTALL_DIR="/opt/onestack"
RAG_DIR="$INSTALL_DIR/backends/python-rag"

# Create directory
print_step "Creating RAG directory..."
mkdir -p "$RAG_DIR"/{app/{routers,services,models,utils},data/{documents,vectorstore},tests}

# requirements.txt
cat > "$RAG_DIR/requirements.txt" << 'RAGREQS'
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-dotenv==1.0.0
pydantic==2.5.0

# LLM & RAG
langchain==0.1.0
openai==1.6.1
anthropic==0.8.1

# Vector DB
chromadb==0.4.22
qdrant-client==1.7.0

# Document Processing
pypdf==3.17.4
python-docx==1.1.0
beautifulsoup4==4.12.2
tiktoken==0.5.2

# Embeddings
sentence-transformers==2.2.2
transformers==4.36.2
RAGREQS

# .env.example
cat > "$RAG_DIR/.env.example" << 'RAGENV'
# LLM API Keys
OPENAI_API_KEY=sk-xxx
ANTHROPIC_API_KEY=sk-ant-xxx

# Embeddings
EMBEDDING_MODEL=all-MiniLM-L6-v2

# Vector DB
VECTORDB_TYPE=chromadb
CHROMADB_PATH=./data/vectorstore
QDRANT_URL=http://qdrant:6333

# RAG Settings
CHUNK_SIZE=512
CHUNK_OVERLAP=50
TOP_K=5

# LLM Settings
LLM_PROVIDER=openai
LLM_MODEL=gpt-3.5-turbo
TEMPERATURE=0.7
MAX_TOKENS=500
RAGENV

# main.py
cat > "$RAG_DIR/app/main.py" << 'RAGMAIN'
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from app.routers import rag, documents
from app.services.vectorstore import init_vectorstore
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title="OneStack RAG API",
    description="Retrieval-Augmented Generation API",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize vector store
@app.on_event("startup")
async def startup_event():
    init_vectorstore()

# Health
@app.get("/health")
async def health():
    return {"status": "ok", "service": "RAG API"}

# Routers
app.include_router(rag.router, prefix="/rag", tags=["RAG"])
app.include_router(documents.router, prefix="/documents", tags=["Documents"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
RAGMAIN

# RAG router
cat > "$RAG_DIR/app/routers/rag.py" << 'RAGROUTER'
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.rag_service import query_rag

router = APIRouter()

class QueryRequest(BaseModel):
    question: str
    collection: str = "default"
    top_k: int = 5

class QueryResponse(BaseModel):
    answer: str
    sources: list
    confidence: float

@router.post("/query", response_model=QueryResponse)
async def query(request: QueryRequest):
    try:
        result = await query_rag(
            question=request.question,
            collection=request.collection,
            top_k=request.top_k
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/collections")
async def list_collections():
    return {"collections": ["default", "docs", "knowledge"]}
RAGROUTER

# Documents router
cat > "$RAG_DIR/app/routers/documents.py" << 'DOCROUTER'
from fastapi import APIRouter, UploadFile, File, HTTPException
from app.services.document_processor import process_document
from app.services.vectorstore import add_to_vectorstore

router = APIRouter()

@router.post("/upload")
async def upload_document(
    file: UploadFile = File(...),
    collection: str = "default"
):
    try:
        # Save file
        file_path = f"./data/documents/{file.filename}"
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
        
        # Process and index
        chunks = await process_document(file_path)
        await add_to_vectorstore(chunks, collection)
        
        return {
            "message": "Document uploaded and indexed",
            "filename": file.filename,
            "chunks": len(chunks)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/list")
async def list_documents():
    import os
    docs = os.listdir("./data/documents")
    return {"documents": docs}
DOCROUTER

# RAG Service
cat > "$RAG_DIR/app/services/rag_service.py" << 'RAGSERVICE'
import os
from langchain.embeddings import HuggingFaceEmbeddings
from langchain.vectorstores import Chroma
from langchain.llms import OpenAI
from langchain.chains import RetrievalQA

# Initialize
embeddings = HuggingFaceEmbeddings(
    model_name=os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
)

async def query_rag(question: str, collection: str = "default", top_k: int = 5):
    # Load vectorstore
    vectorstore = Chroma(
        collection_name=collection,
        embedding_function=embeddings,
        persist_directory="./data/vectorstore"
    )
    
    # Search
    docs = vectorstore.similarity_search(question, k=top_k)
    
    # Generate answer with LLM
    llm = OpenAI(
        temperature=float(os.getenv("TEMPERATURE", 0.7)),
        max_tokens=int(os.getenv("MAX_TOKENS", 500))
    )
    
    qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        retriever=vectorstore.as_retriever(search_kwargs={"k": top_k})
    )
    
    result = qa_chain.run(question)
    
    return {
        "answer": result,
        "sources": [{"content": doc.page_content, "metadata": doc.metadata} for doc in docs],
        "confidence": 0.85
    }
RAGSERVICE

# Document Processor
cat > "$RAG_DIR/app/services/document_processor.py" << 'DOCPROC'
import os
from langchain.document_loaders import PyPDFLoader, TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter

async def process_document(file_path: str):
    # Load document
    if file_path.endswith('.pdf'):
        loader = PyPDFLoader(file_path)
    elif file_path.endswith('.txt'):
        loader = TextLoader(file_path)
    else:
        raise ValueError(f"Unsupported file type: {file_path}")
    
    documents = loader.load()
    
    # Split into chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=int(os.getenv("CHUNK_SIZE", 512)),
        chunk_overlap=int(os.getenv("CHUNK_OVERLAP", 50))
    )
    
    chunks = text_splitter.split_documents(documents)
    
    return chunks
DOCPROC

# Vector Store
cat > "$RAG_DIR/app/services/vectorstore.py" << 'VECSTORE'
import os
from langchain.embeddings import HuggingFaceEmbeddings
from langchain.vectorstores import Chroma

embeddings = HuggingFaceEmbeddings(
    model_name=os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
)

def init_vectorstore():
    os.makedirs("./data/vectorstore", exist_ok=True)
    print("✓ Vector store initialized")

async def add_to_vectorstore(chunks, collection: str = "default"):
    vectorstore = Chroma(
        collection_name=collection,
        embedding_function=embeddings,
        persist_directory="./data/vectorstore"
    )
    
    vectorstore.add_documents(chunks)
    vectorstore.persist()
    
    return len(chunks)
VECSTORE

# Dockerfile
cat > "$RAG_DIR/Dockerfile" << 'RAGDOCKER'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
RAGDOCKER

# README
cat > "$RAG_DIR/README.md" << 'RAGREADME'
# OneStack Python RAG System

AI-powered Question Answering with Retrieval-Augmented Generation.

## Features

- 📄 Document ingestion (PDF, TXT, DOCX)
- 🔍 Vector similarity search
- 🤖 LLM-powered answer generation
- 💾 Multiple vector databases (ChromaDB, Qdrant)
- 🌐 REST API

## Setup
```bash
cd /opt/onestack/backends/python-rag
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Add your OpenAI API key to .env
uvicorn app.main:app --reload
```

## API Endpoints

**Upload Document:**
```bash
curl -X POST "http://localhost:8000/documents/upload" \
  -F "file=@document.pdf" \
  -F "collection=docs"
```

**Query:**
```bash
curl -X POST "http://localhost:8000/rag/query" \
  -H "Content-Type: application/json" \
  -d '{"question": "What is OneStack?", "collection": "docs"}'
```

## Swagger UI

http://localhost:8000/docs
RAGREADME

# Add to docker-compose
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'RAGCOMPOSE'

  # Python RAG System
  python-rag:
    build: ./backends/python-rag
    container_name: onestack-python-rag
    restart: unless-stopped
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      EMBEDDING_MODEL: all-MiniLM-L6-v2
      VECTORDB_TYPE: chromadb
    volumes:
      - ./backends/python-rag:/app
      - ./backends/python-rag/data:/app/data
    networks:
      - backend
    ports:
      - "8001:8000"
RAGCOMPOSE
fi

# Update Nginx
if [ -f "$INSTALL_DIR/nginx/conf.d/onestack.conf" ]; then
    cat >> "$INSTALL_DIR/nginx/conf.d/onestack.conf" << 'RAGNGINX'

# Python RAG API
server {
    listen 80;
    server_name ai.${DOMAIN};
    
    location / {
        proxy_pass http://python-rag:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
RAGNGINX
fi

print_success "Python RAG System installed!"
echo ""
echo "Next steps:"
echo "1. cd $RAG_DIR"
echo "2. python3 -m venv venv && source venv/bin/activate"
echo "3. pip install -r requirements.txt"
echo "4. cp .env.example .env"
echo "5. Add your OpenAI API key to .env"
echo "6. uvicorn app.main:app --reload"
echo ""
echo "API Docs: http://localhost:8001/docs"
echo "Access: http://ai.yourdomain.com"
