// server.js
const path = require('path'); 
require('dotenv').config({ path: path.join(__dirname, '.env') }); 
console.log("Loaded ANTHROPIC_API_KEY from .env:", process.env.ANTHROPIC_API_KEY);
const express = require('express');
const { Anthropic } = require('@anthropic-ai/sdk');
const axios = require('axios'); 

const app = express();
const port = process.env.PORT || 3000;
const USE_MOCK_CLAUDE = process.env.USE_MOCK_CLAUDE === 'true'; 

// Renamed to avoid confusion with Anthropic's Model Context Protocol (MCP)
const MARKET_DATA_SERVER_URL = process.env.MARKET_DATA_SERVER_URL || 'http://localhost:3001';

// Placeholder: Replace with the actual URL of your running Hacker News guMCP server
const HACKERNEWS_GUMCP_SERVER_URL = process.env.HACKERNEWS_GUMCP_SERVER_URL || 'http://localhost:8000/hackernews/local';
// Placeholder: Replace with the actual tool name exposed by the HN guMCP server for searching stories/comments
const HACKERNEWS_GUMCP_TOOL_NAME = 'get_top_stories'; // Updated based on HN guMCP README

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

app.use(express.json());
app.use(express.static('public')); 

// Renamed to avoid confusion with Anthropic's Model Context Protocol (MCP)
async function getMarketDataContext(country, industry) {
  try {
    // Note: The original call used capability: 'get_simulated_market_data'.
    // This remains if this server is still primarily for simulated/mock broader market data.
    const response = await axios.post(`${MARKET_DATA_SERVER_URL}/call-capability`, {
      capability: 'get_simulated_market_data', // Or a more generic capability name
      args: { country, industry }
    });

    if (response.status === 200 && response.data) {
      const marketData = typeof response.data === 'string'
        ? JSON.parse(response.data)
        : response.data;
      return marketData;
    } else {
      console.error("Error response from Market Data server:", response.status, response.data);
      return {
        error: "Failed to retrieve data from Market Data server",
        status: response.status
      };
    }
  } catch (error) {
    console.error("Error calling Market Data server:", error.message);
    return {
      error: "Failed to connect to Market Data server. Is it running?",
      details: error.message
    };
  }
}

async function getHackerNewsContext(industryKeyword) {
  if (!HACKERNEWS_GUMCP_SERVER_URL || HACKERNEWS_GUMCP_SERVER_URL === 'http://localhost:3002/mcp') {
    console.warn("HACKERNEWS_GUMCP_SERVER_URL is not configured or using an old default. Ensure it points to the correct /hackernews/local endpoint (e.g., http://localhost:8000/hackernews/local). Skipping Hacker News context.");
    return "Hacker News context fetching is not configured correctly.";
  }

  try {
    const mcpRequestBody = {
      jsonrpc: "2.0",
      method: "call_tool",
      params: {
        tool_name: HACKERNEWS_GUMCP_TOOL_NAME,
        tool_input: {
          limit: 7
        }
      },
      id: "binah-hn-request-" + Date.now()
    };

    console.log(`Querying Hacker News guMCP server at ${HACKERNEWS_GUMCP_SERVER_URL} with tool ${HACKERNEWS_GUMCP_TOOL_NAME}`);
    const response = await axios.post(HACKERNEWS_GUMCP_SERVER_URL, mcpRequestBody, {
      headers: { 'Content-Type': 'application/json' },
      timeout: 7000
    });

    if (response.data && response.data.result && response.data.result.content) {
      console.log("Received data from Hacker News guMCP server (get_top_stories).");
      let formattedContext = "Hacker News - Top Stories Context:\\n";
      let storiesProcessed = 0;
      if (Array.isArray(response.data.result.content)) {
        for (const item of response.data.result.content) {
          let storyTitle = null;
          let storyUrl = null;
          let storyText = null;

          if (typeof item === 'string') {
            storyTitle = item;
          } else if (item && item.title) {
            storyTitle = item.title;
            storyUrl = item.url || (item.link_url || (item.id ? `https://news.ycombinator.com/item?id=${item.id}` : null));
            storyText = item.text || item.snippet;
          } else if (item && item.text && !item.title) {
            storyTitle = item.text.substring(0,100) + "... (potential comment/post)";
            storyUrl = item.id ? `https://news.ycombinator.com/item?id=${item.id}` : null;
          }

          if (storyTitle) {
            if (industryKeyword && industryKeyword.trim() !== "" && !storyTitle.toLowerCase().includes(industryKeyword.toLowerCase())) {
            }
            formattedContext += `- ${storyTitle}`;
            if (storyUrl) {
              formattedContext += ` (Link: ${storyUrl})`;
            }
            if (storyText && storyTitle !== storyText.substring(0,100) + "... (potential comment/post)") {
                formattedContext += ` - Snippet: ${storyText.substring(0, 100)}...`;
            }
            formattedContext += "\\n";
            storiesProcessed++;
          }
        }
      }
      return storiesProcessed > 0 ? formattedContext.trim() : "No relevant Hacker News top stories processed or found in expected format.";
    } else {
      console.warn("Hacker News guMCP server (get_top_stories) returned an unexpected response format:", JSON.stringify(response.data, null, 2));
      return "Could not retrieve Hacker News top stories due to response format.";
    }
  } catch (error) {
    console.error(`Error calling Hacker News guMCP server (get_top_stories) for '${industryKeyword}':`, error.message);
    if (error.code === 'ECONNREFUSED') {
        return "Failed to connect to Hacker News context service (ECONNREFUSED). Is the guMCP SSE server running on the configured URL and port (e.g. http://localhost:8000/hackernews/local)?";
    }
    if (error.response) {
      console.error("HN guMCP Error Response Data:", JSON.stringify(error.response.data, null, 2));
    }
    return "Failed to retrieve Hacker News top stories due to an error.";
  }
}

function getMockClaudeResponse(industry, country) {
  console.log(`Using MOCK Claude response for ${industry} in ${country}`);
  return {
    strategic_summary: `This is a mock strategic summary for ${industry} in ${country}. The market shows potential but requires careful planning.`,
    key_opportunities: [`Mock opportunity for ${industry}: Leverage digital transformation trends.`, `Mock opportunity 2: Target niche segments in ${country}.`],
    cultural_considerations: [`Mock cultural tip: Understand local business etiquette in ${country}.`, `Mock cultural tip 2: Adapt communication styles.`],
    regulatory_landscape: [`Mock regulatory point: Be aware of data privacy laws in ${country}.`, `Mock regulatory point 2: Check industry-specific licenses.`],
    initial_action_plan: [
        {action: `Conduct detailed market research for ${industry} in ${country}.`, rationale: "Essential to understand market size, competition, and customer needs."},
        {action: "Identify potential local partners or distributors.", rationale: "Local expertise can accelerate market entry."},
        {action: "Develop a localized marketing and sales strategy.", rationale: `Tailoring your message to ${country}'s culture is key.`}
    ],
    key_resources_and_searches: {
        suggested_search_queries: [`${industry} market size ${country}`, `business registration ${country}`, `${industry} regulations ${country}`],
        relevant_agencies_bodies: [`Mock Chamber of Commerce ${country}`, `Mock Industry Association for ${industry}`]
    },
    competitive_overview: {
        potential_competitor_types: [`Local ${industry} companies in ${country}`, `International ${industry} companies operating in ${country}`],
        example_players_to_research: [`MockCompetitor A (${country})`, `GlobalPlayer Inc.`]
    },
    risk_factors_and_success_drivers: {
        potential_challenges: [`Navigating bureaucracy in ${country}`, `Intense competition from established players.`],
        critical_success_factors: [`Strong value proposition tailored to ${country}.`, `Effective local partnerships.`]
    },
    further_research_links_from_context: [
        {title: "Mock Search Result 1", link: "#", relevance_note: "This mock link is important for initial research."}
    ],
    mvp_pitch: `Mock MVP pitch for ${industry} in ${country}: This revolutionary app will simplify X by leveraging Y, offering Z benefit.`,
    value_proposition_points: [
        `Mock Value Prop 1: Streamlines ${industry} tasks.`,
        `Mock Value Prop 2: Unique approach to ${country} market.`,
        `Mock Value Prop 3: Easy to integrate and use.`
    ],
    vibe_code_app_idea: {
      "concept": `Mock Vibe Code App for ${industry}: A simple tool to quickly find local ${industry} suppliers in ${country} based on user-provided keywords.`,
      "target_user_persona": `Small business owners in ${country} looking for ${industry} resources.`,
      "justification_for_vibe_coding": "Simple CRUD operations and UI, ideal for AI generation and quick validation.",
      "example_vibe_code_prompt_for_ai": `Create a one-page web app titled '${industry} Supplier Finder for ${country}'. It needs an input field for a keyword (e.g., 'organic cotton') and a button. When clicked, it shows a list of mock supplier names and contacts based on the keyword.`
    },
    vibe_code_app_marketing_channels: [
        `Post on relevant small business forums in ${country}.`,
        `Share in LinkedIn groups for ${industry} professionals in ${country}.`,
        `Targeted Facebook ads to small business owners in ${country}.`
    ]
  };
}

function extractJSON(text) {
  const jsonMatch = text.match(/{[\s\S]*}/);
  if (jsonMatch && jsonMatch[0]) {
    try {
      return JSON.parse(jsonMatch[0]);
    } catch (e) {
      console.warn(`extractJSON: Initial JSON.parse failed for block: ${jsonMatch[0]}. Error: ${e.message}`);
    }
  }
  console.warn("extractJSON: Could not find a clear JSON block or initial parse failed. Full text:", text);
  return null; 
}

app.get('/test-claude', async (req, res) => {
  if (USE_MOCK_CLAUDE) {
    return res.json({ success: true, response: getMockClaudeResponse("TestIndustry", "TestCountry") });
  }
  try {
    const completion = await anthropic.completions.create({
      model: 'claude-2.1',
      prompt: `${Anthropic.HUMAN_PROMPT} Hi Claude, please respond with a short, friendly greeting. ${Anthropic.AI_PROMPT}`,
      max_tokens_to_sample: 100,
    });
    res.json({ success: true, response: completion.completion });
  } catch (error) {
    console.error('Error calling Claude:', error);
    res.status(500).json({ success: false, error: 'Failed to call Claude' });
  }
});

app.post('/api/analyze', async (req, res) => {
  console.log("--- !!! BINAH /api/analyze ROUTE ENTERED !!! --- Timestamp:", new Date().toISOString());

  const { industry, country } = req.body;

  if (!industry || !country) {
    console.log("/api/analyze - Missing industry or country");
    return res.status(400).json({ success: false, error: 'Industry and country are required.' });
  }

  // Mock handling for Claude response should still generate insights.
  // Hacker News context can also be mocked if USE_MOCK_CLAUDE is true.
  if (USE_MOCK_CLAUDE) {
    console.log("/api/analyze - Using MOCK Claude response and MOCK Hacker News context");
    const mockInsights = getMockClaudeResponse(industry, country);
    // Add mock Hacker News context directly to the insights for simplicity if needed by frontend for display,
    // OR ensure the mock prompt generation below includes it if only Claude sees it.
    // For now, we'll mock it for the prompt construction part.
    const mockHackerNewsContext = `Hacker News Context (Mocked for ${industry} - Top Stories):\\n- HN Story 1: ${industry} sees breakthrough innovation!\\n- HN Story 2: Top VCs investing heavily in ${industry} sector.\\n- HN Story 3: A new open-source project for ${industry} developers.`;
    
    // Construct a simplified prompt for logging or if we were to actually call Claude with mock context
    const marketData = { /* minimal mock marketData if needed by prompt construction */ };
    const officialNameInfo = ''; const regionInfo = ''; const populationInfo = '';
    let liveWebSearchesPromptSection = "No live web searches (mock mode)."; // from old system
    
    const promptForMock = prepareClaudePrompt(industry, country, officialNameInfo, regionInfo, populationInfo, marketData, liveWebSearchesPromptSection, mockHackerNewsContext);
    console.log("--- Mock Claude Prompt (for context) --- \n", promptForMock);
    
    return res.json({ success: true, insights: mockInsights, source: 'mock_claude_with_mock_hn_context' });
  }

  try {
    console.log(`/api/analyze - Fetching Market Data Context for ${industry}, ${country}`);
    const marketData = await getMarketDataContext(country, industry); // Renamed function

    if (marketData.error) {
      console.error("/api/analyze - Market Data Context Error:", marketData.error, marketData.details || "");
      // Fallback to mock Claude response if primary market data fails
      const mockFallbackInsights = getMockClaudeResponse(industry, country);
      return res.status(500).json({
        success: true,
        insights: mockFallbackInsights,
        source: 'mock_claude_due_to_market_data_error',
        error_details: marketData.error
      });
    }
    console.log("/api/analyze - Market Data Context fetched successfully. It includes live_web_searches:", !!marketData.live_web_searches);

    const officialNameInfo = (marketData.official_name && marketData.official_name.toLowerCase() !== country.toLowerCase())
      ? ` (Official Name: ${marketData.official_name})`
      : '';
    const regionInfo = marketData.real_region
      ? `(located in ${marketData.real_region}${marketData.real_subregion ? ', ' + marketData.real_subregion : ''})`
      : '(region unspecified)';
    const populationInfo = (marketData.real_population && typeof marketData.real_population === 'number')
      ? `, with an approximate population of ${marketData.real_population.toLocaleString()}`
      : '';

    let liveWebSearchesPromptSection = "No traditional web search results available.";
    if (marketData.live_web_searches && Object.keys(marketData.live_web_searches).length > 0) {
        liveWebSearchesPromptSection = "Traditional Web Search Snippets (Top 2 results for each query):\n";
        for (const category in marketData.live_web_searches) {
            if (Array.isArray(marketData.live_web_searches[category]) && marketData.live_web_searches[category].length > 0) {
                liveWebSearchesPromptSection += `\nResults for "${category.replace(/_/g, ' ')}":\n`;
                marketData.live_web_searches[category].forEach(result => {
                    liveWebSearchesPromptSection += `  - Title: ${result.title}\n    Link: ${result.link}\n    Snippet: ${result.snippet}\n`;
                });
            } else if (marketData.live_web_searches[category].note) {
                 liveWebSearchesPromptSection += `\nNote for "${category.replace(/_/g, ' ')}": ${marketData.live_web_searches[category].note}\n`;
            }
        }
    }
    
    // Fetch Hacker News Context
    console.log(`/api/analyze - Fetching Hacker News Context for ${industry} via guMCP`);
    const hackerNewsContext = await getHackerNewsContext(industry);
    const hackerNewsPromptSection = hackerNewsContext || "No specific Hacker News context was retrieved for this query.";

    const prompt = prepareClaudePrompt(industry, country, officialNameInfo, regionInfo, populationInfo, marketData, liveWebSearchesPromptSection, hackerNewsPromptSection);
    
    console.log("--- Full Prompt to Claude --- \n", prompt);

    const completion = await anthropic.completions.create({
      model: 'claude-2.1', 
      prompt: prompt,
      max_tokens_to_sample: 2000, // Increased for potentially richer content from web searches
      temperature: 0.2, 
    });

    let insights;
    const rawCompletion = completion.completion.trim();
    try {
      insights = JSON.parse(rawCompletion);
      console.log("/api/analyze - Successfully parsed rawCompletion with JSON.parse");
    } catch (parseError) {
      console.warn(`/api/analyze - Initial JSON.parse failed. Error: ${parseError.message}. Attempting extractJSON. Raw completion from Claude was:\n---\n${rawCompletion}\n---`);
      insights = extractJSON(rawCompletion); 
      if (!insights) {
        console.error("/api/analyze - extractJSON also failed. Raw completion was:\n---\n" + rawCompletion + "\n---");
        insights = { 
            raw_response_on_error: rawCompletion, 
            error_message: "Failed to parse structured JSON from Claude after multiple attempts." 
        };
      } else {
        console.log("/api/analyze - Successfully parsed insights using extractJSON fallback.");
      }
    }

    console.log("--- Claude Insights Received (Parsed/Extracted) --- \n", JSON.stringify(insights, null, 2)); 

    res.json({ success: true, insights: insights, source: 'claude_api', rawClaudeResponseForDebug: rawCompletion });

  } catch (error) {
    console.error('/api/analyze - Error in overall try block:', error);
    if (error.name === 'AnthropicAPIError' || error.status) {
         const mockFallbackInsights = getMockClaudeResponse(industry, country);
         res.status(500).json({ success: true, insights: mockFallbackInsights, source: 'mock_claude_due_to_api_error', error_details: error.message });
    } else {
        res.status(500).json({ success: false, error: 'Failed to generate insights. Internal server error.' });
    }
  }
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
  // console.log(`MCP client configured to connect to ${MCP_SERVER_URL}`); // Old log
  console.log(`Market Data client configured to connect to ${MARKET_DATA_SERVER_URL}`);
  console.log(`Hacker News guMCP client configured to connect to ${HACKERNEWS_GUMCP_SERVER_URL} (tool: ${HACKERNEWS_GUMCP_TOOL_NAME})`);
  if (USE_MOCK_CLAUDE) {
    console.warn("WARNING: USE_MOCK_CLAUDE is true. Real Anthropic API calls will be skipped.");
  }
});

// Helper function to construct the prompt - makes /api/analyze cleaner
function prepareClaudePrompt(industry, country, officialNameInfo, regionInfo, populationInfo, marketData, liveWebSearchesPromptSection, hackerNewsPromptSection) {
  return `
${Anthropic.HUMAN_PROMPT}
You are an expert AI International Market Entry Strategist. Your goal is to provide a comprehensive, actionable initial analysis for a startup, synthesizing all available information.

**Startup Profile:**
*   Industry: "${industry}"
*   Target Market: "${country}"${officialNameInfo} ${regionInfo}${populationInfo}.

**Contextual Information for "${country}" (from primary data source):**
*   Official Name: ${marketData.official_name || 'N/A'}
*   Region: ${marketData.real_region || 'N/A'} (${marketData.real_subregion || 'N/A'})
*   Approx. Population: ${marketData.real_population ? marketData.real_population.toLocaleString() : 'N/A'}
*   Market Summary (from primary data source): ${marketData.market_summary || 'No specific market summary available.'}
*   Cultural Tips (from primary data source): ${marketData.cultural_tips || 'No specific cultural tips available.'}
*   Regulatory Overview (from primary data source): ${marketData.regulatory_overview || 'No specific regulatory overview available.'}

**${liveWebSearchesPromptSection}**

**${hackerNewsPromptSection}**

Based EXCLUSIVELY on the Startup Profile and ALL Contextual Information provided above (including Traditional Web Search and Hacker News Context), please generate a detailed strategic analysis. You MUST use and synthesize information from ALL provided context sections for each relevant category of your analysis. Explicitly state if your insights are drawn from the web search snippets or Hacker News context where applicable.

**REQUIRED OUTPUT STRUCTURE:**
Your response MUST be a single, valid JSON object. Do NOT include any introductory text, conversational phrases, or explanations outside of the JSON structure itself. The JSON object must have the following top-level keys, with values as described:

1.  **\`strategic_summary\`**: (String) A concise (2-3 sentences) overall strategic assessment.
2.  **\`key_opportunities\`**: (Array of Strings) 2-4 distinct market opportunities, informed by all data.
3.  **\`cultural_considerations\`**: (Array of Strings) 2-4 crucial cultural points.
4.  **\`regulatory_landscape\`**: (Array of Strings) 2-4 key regulatory points, informed by web search snippets or Hacker News context if relevant.
5.  **\`initial_action_plan\`**: (Array of Objects) 3-5 items. Each object: {"action": (String), "rationale": (String)}.
6.  **\`key_resources_and_searches\`**: (Object) {"suggested_search_queries": (Array of Strings), "relevant_agencies_bodies": (Array of Strings)}.
7.  **\`competitive_overview\`**: (Object) {"potential_competitor_types": (Array of Strings), "example_players_to_research": (Array of Strings - names or types, informed by web search snippets or Hacker News context if relevant)}.
8.  **\`risk_factors_and_success_drivers\`**: (Object) {"potential_challenges": (Array of Strings), "critical_success_factors": (Array of Strings)}.
9.  **\`further_research_links_from_context\`**: (Array of Objects) Analyze ALL provided context (Traditional Web Search Snippets AND Hacker News Context). Select the 2-3 most relevant web links OR discussion threads/stories from those contexts that the user should prioritize. For each, provide: {"title": (String - original title from snippet/story), "link": (String - original link if available, otherwise a link to the HN discussion if possible, or "#" if no link), "relevance_note": (String - brief note on why it's particularly relevant for the startup)}. If no context was available or none seem highly relevant, return an empty array.
10. **\`mvp_pitch\`**: (String) Based on your overall strategic analysis for the given product/industry and country, provide a compelling 2-3 sentence pitch for a hypothetical Minimum Viable Product (MVP).
11. **\`value_proposition_points\`**: (Array of Strings) Based on your overall strategic analysis, list 3 concise bullet points highlighting the core value proposition of such an MVP.
12. **\`vibe_code_app_idea\`**: (Object) Based on the overall analysis, provide an idea for a very simple application that could be rapidly prototyped using a "vibe coding" approach (describing it to an AI for code generation). The object must contain:
    **\`concept\`**: (String) 1-2 sentence description of the app\'s core function.
    **\`target_user_persona\`**: (String) 1 sentence describing the primary target user.
    **\`justification_for_vibe_coding\`**: (String) 1 sentence explaining why it\'s suitable for vibe coding (e.g., simple scope, focus on quick validation).
    **\`example_vibe_code_prompt_for_ai\`**: (String) A 2-3 sentence example prompt a user could give to an AI coding assistant to start building this app.
13. **\`vibe_code_app_marketing_channels\`**: (Array of Strings) Suggest 2-3 specific, low-cost marketing channels or platforms effective for quickly reaching target users of this proposed vibe code app prototype.

**EXAMPLE OF THE \`initial_action_plan\` item structure:**
{ "action": "Conduct detailed competitor analysis.", "rationale": "Essential for market positioning." }

**IMPORTANT REMINDERS:**
*   Adhere STRICTLY to the JSON structure.
*   Base analysis ONLY on provided context.
*   If web snippets or Hacker News context inform a point, you can briefly mention it (e.g., "Hacker News discussions suggest X is a key factor.").

${Anthropic.AI_PROMPT}
`;
}