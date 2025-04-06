# Phase 1: Project Setup and Basic LLM Integration

This tutorial will guide you through the first phase of building a practical Go application that demonstrates how to work with Large Language Models (LLMs). In Phase 1, we'll focus on setting up the project structure and implementing basic LLM integration.

## Prerequisites

Before starting, ensure you have:
- Go 1.21+ installed
- Access to an LLM provider (API key or local model)
- Basic understanding of Go programming

## 1. Project Initialization

### Setting up the Go Module

Let's start by creating a new Go module for our project:

```bash
mkdir -p llm-demo
cd llm-demo
go mod init github.com/yourusername/llm-demo
```

### Project Structure

Following Go best practices, we'll organize our project using the standard Go project layout:

```
llm-demo/
├── cmd/                    # Command-line applications
│   └── llm-demo/           # Main application entry point
├── internal/               # Private application code
│   ├── llm/                # LLM integration logic
│   ├── prompt/             # Prompt templates and engineering
│   └── config/             # Configuration handling
├── pkg/                    # Public library code
│   ├── models/             # Data models and interfaces
│   └── utils/              # Utility functions
├── go.mod                  # Go module definition
├── go.sum                  # Go module checksums
└── README.md               # Project documentation
```

Let's create this structure:

```bash
mkdir -p cmd/llm-demo
mkdir -p internal/llm internal/prompt internal/config
mkdir -p pkg/models pkg/utils
touch README.md
```

### Configuration Handling

We'll create a simple configuration package to handle environment variables and settings:

```go
// internal/config/config.go
package config

import (
	"errors"
	"os"
)

// Config holds the application configuration
type Config struct {
	LLMProvider string
	APIKey      string
	ModelName   string
	MaxTokens   int
}

// LoadConfig loads the configuration from environment variables
func LoadConfig() (*Config, error) {
	apiKey := os.Getenv("LLM_API_KEY")
	if apiKey == "" {
		return nil, errors.New("LLM_API_KEY environment variable is required")
	}

	provider := os.Getenv("LLM_PROVIDER")
	if provider == "" {
		provider = "openai" // Default provider
	}

	modelName := os.Getenv("LLM_MODEL_NAME")
	if modelName == "" {
		modelName = "gpt-3.5-turbo" // Default model
	}

	maxTokens := 1024 // Default max tokens

	return &Config{
		LLMProvider: provider,
		APIKey:      apiKey,
		ModelName:   modelName,
		MaxTokens:   maxTokens,
	}, nil
}
```

## 2. LLM Client Integration

Now, let's implement the LLM client integration. We'll start by adding the necessary dependencies:

```bash
go get github.com/sashabaranov/go-openai
```

### Implementing the LLM Client

Create a client for interacting with the LLM:

```go
// internal/llm/client.go
package llm

import (
	"context"
	"errors"
	"time"

	"github.com/sashabaranov/go-openai"
	"github.com/yourusername/llm-demo/internal/config"
)

// Client represents an LLM client
type Client struct {
	openAIClient *openai.Client
	config       *config.Config
}

// NewClient creates a new LLM client
func NewClient(cfg *config.Config) (*Client, error) {
	if cfg.LLMProvider != "openai" {
		return nil, errors.New("only OpenAI provider is supported at the moment")
	}

	client := openai.NewClient(cfg.APIKey)
	return &Client{
		openAIClient: client,
		config:       cfg,
	}, nil
}

// Complete sends a completion request to the LLM
func (c *Client) Complete(ctx context.Context, prompt string) (string, error) {
	// Create a context with timeout
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	// Create the request
	req := openai.ChatCompletionRequest{
		Model: c.config.ModelName,
		Messages: []openai.ChatCompletionMessage{
			{
				Role:    openai.ChatMessageRoleUser,
				Content: prompt,
			},
		},
		MaxTokens: c.config.MaxTokens,
	}

	// Send the request
	resp, err := c.openAIClient.CreateChatCompletion(ctx, req)
	if err != nil {
		return "", err
	}

	// Check if we have a response
	if len(resp.Choices) == 0 {
		return "", errors.New("no response from LLM")
	}

	return resp.Choices[0].Message.Content, nil
}
```

### Error Handling and Retry Logic

Let's add some basic retry logic:

```go
// internal/llm/retry.go
package llm

import (
	"context"
	"errors"
	"time"
)

// RetryOptions configures the retry behavior
type RetryOptions struct {
	MaxRetries  int
	InitialWait time.Duration
	MaxWait     time.Duration
}

// DefaultRetryOptions returns the default retry options
func DefaultRetryOptions() RetryOptions {
	return RetryOptions{
		MaxRetries:  3,
		InitialWait: 1 * time.Second,
		MaxWait:     10 * time.Second,
	}
}

// CompleteWithRetry attempts to complete a prompt with retries
func (c *Client) CompleteWithRetry(ctx context.Context, prompt string, opts RetryOptions) (string, error) {
	var lastErr error
	wait := opts.InitialWait

	for attempt := 0; attempt <= opts.MaxRetries; attempt++ {
		// If not the first attempt, wait before retrying
		if attempt > 0 {
			select {
			case <-time.After(wait):
				// Double the wait time for the next attempt, but cap it
				wait *= 2
				if wait > opts.MaxWait {
					wait = opts.MaxWait
				}
			case <-ctx.Done():
				return "", errors.New("operation canceled or timed out")
			}
		}

		// Attempt the completion
		result, err := c.Complete(ctx, prompt)
		if err == nil {
			return result, nil
		}

		lastErr = err
	}

	return "", errors.New("max retries exceeded: " + lastErr.Error())
}
```

## 3. Simple CLI Demo

Now, let's create a simple command-line interface to interact with our LLM:

```go
// cmd/llm-demo/main.go
package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/yourusername/llm-demo/internal/config"
	"github.com/yourusername/llm-demo/internal/llm"
)

func main() {
	// Set up logging
	log.SetPrefix("LLM-Demo: ")
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)

	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Create LLM client
	client, err := llm.NewClient(cfg)
	if err != nil {
		log.Fatalf("Failed to create LLM client: %v", err)
	}

	// Create a scanner for reading user input
	scanner := bufio.NewScanner(os.Stdin)

	fmt.Println("Welcome to the LLM Demo!")
	fmt.Println("Type your prompts and press Enter. Type 'exit' to quit.")

	// Main interaction loop
	for {
		fmt.Print("> ")
		if !scanner.Scan() {
			break
		}

		input := scanner.Text()
		if strings.ToLower(input) == "exit" {
			break
		}

		// Skip empty inputs
		if strings.TrimSpace(input) == "" {
			continue
		}

		// Send the prompt to the LLM
		fmt.Println("Thinking...")
		response, err := client.CompleteWithRetry(
			context.Background(),
			input,
			llm.DefaultRetryOptions(),
		)

		if err != nil {
			log.Printf("Error: %v", err)
			continue
		}

		// Display the response
		fmt.Println("\nResponse:")
		fmt.Println(response)
		fmt.Println()
	}

	if err := scanner.Err(); err != nil {
		log.Printf("Error reading input: %v", err)
	}

	fmt.Println("Goodbye!")
}
```

## Building and Running the Application

Let's build and run our application:

```bash
# Build the application
go build -o llm-demo ./cmd/llm-demo

# Set the required environment variables
export LLM_API_KEY="your-api-key-here"
export LLM_PROVIDER="openai"
export LLM_MODEL_NAME="gpt-3.5-turbo"

# Run the application
./llm-demo
```

## Next Steps

In this phase, we've set up the basic project structure and implemented a simple LLM client with a command-line interface. In Phase 2, we'll build on this foundation to add more advanced features like prompt engineering, context window management, and streaming responses.

Key accomplishments in Phase 1:
- Set up a well-structured Go project
- Implemented configuration handling
- Created an LLM client with OpenAI integration
- Added basic error handling and retry logic
- Built a simple CLI for interacting with the LLM

In the next phase, we'll explore more advanced LLM features and continue building our application.
