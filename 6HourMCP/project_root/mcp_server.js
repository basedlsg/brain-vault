const express = require('express');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
require('dotenv').config({ path: path.join(__dirname, '.env') }); // For SERPAPI_API_KEY

const app = express();
const port = 3001;

app.use(express.json());

// --- SerpAPI Key ---
const SERPAPI_API_KEY = process.env.SERPAPI_API_KEY;
if (!SERPAPI_API_KEY) {
    console.warn("[MCP Server] WARNING: SERPAPI_API_KEY not found in .env. Live web searches will be skipped.");
}

// --- Data Loading ---
const MOCK_DATA_PATH = path.join(__dirname, 'mock_data.json'); // Assumes mcp_server.js is in project_root
let allData = {};

try {
  const rawData = fs.readFileSync(MOCK_DATA_PATH);
  allData = JSON.parse(rawData);
  console.log(`[MCP Server] Successfully loaded data from ${MOCK_DATA_PATH}`);
} catch (error) {
  console.error(`[MCP Server] CRITICAL ERROR: Failed to load mock_data.json from ${MOCK_DATA_PATH}. Server will not function correctly.`, error);
  // In a real scenario, you might want to prevent the server from starting or have a more robust fallback.
  allData = {}; // Ensure allData is an empty object to prevent crashes if accessed.
}

// --- Helper function to get base data ---
function getBaseMarketData(country, industry) {
  if (Object.keys(allData).length === 0) {
    return {
      error: "Mock data is not loaded. Check server logs.",
      market_summary: "Error: Data source unavailable.",
      cultural_tips: "Error: Data source unavailable.",
      regulatory_overview: "Error: Data source unavailable."
    };
  }
  if (allData[country] && allData[country][industry]) {
    return { ...allData[country][industry] }; // Return a copy to avoid modifying original mock data
  } else if (allData[country]) {
    console.log(`[MCP Server] Base data for ${country} - ${industry} not found. Falling back to general ${country} data.`);
    return {
      market_summary: `General market data for ${country}. Specific data for ${industry} not in mock set.`,
      cultural_tips: `General cultural tips for ${country}.`,
      regulatory_overview: `General regulatory overview for ${country}.`
    };
  } else {
    console.log(`[MCP Server] Base data for ${country} not found. Returning generic international data.`);
    return {
      market_summary: `No specific mock data for ${country} or the ${industry} sector. General international market conditions apply.`,
      cultural_tips: "Standard international business etiquette recommended.",
      regulatory_overview: "General international trade regulations apply. Specific research needed."
    };
  }
}

// --- Helper function for SerpAPI search ---
async function performSerpAPISearch(query, apiKey) {
    if (!apiKey) {
        console.log("[MCP Server] SerpAPI key missing, skipping search for:", query);
        return [];
    }
    try {
        const searchUrl = `https://serpapi.com/search.json?q=${encodeURIComponent(query)}&api_key=${apiKey}&num=2`; // Get top 2 results
        console.log(`[MCP Server] Performing SerpAPI search: ${query}`);
        const response = await axios.get(searchUrl, { timeout: 10000 }); // 10 second timeout
        if (response.data && response.data.organic_results) {
            return response.data.organic_results.slice(0, 2).map(result => ({
                title: result.title,
                link: result.link,
                snippet: result.snippet
            }));
        }
        console.warn(`[MCP Server] SerpAPI search for "${query}" did not return organic_results.`);
        return [];
    } catch (error) {
        console.error(`[MCP Server] Error performing SerpAPI search for "${query}": ${error.message}`);
        if (error.response) {
            console.error(`[MCP Server] SerpAPI Error Details: Status ${error.response.status}, Data:`, error.response.data);
        }
        return []; // Return empty array on error
    }
}

// --- Endpoint to call capabilities ---
app.post('/call-capability', async (req, res) => {
  const { capability, args } = req.body;
  console.log(`[MCP Server] Received /call-capability: ${capability} with args:`, args);

  if (!capability) {
    return res.status(400).json({ error: 'Capability name is required.' });
  }

  if (capability === 'get_simulated_market_data') {
    if (!args || !args.country || !args.industry) {
      return res.status(400).json({ error: 'Missing country or industry in args for get_simulated_market_data.' });
    }
    const { country, industry } = args;
    let marketData = getBaseMarketData(country, industry); // Use let as it might be augmented
    
    if (marketData.error && marketData.error === "Mock data is not loaded. Check server logs.") {
        console.error("[MCP Server] Responding with error because mock data is not loaded.");
        return res.status(500).json(marketData);
    }

    // If baseMarketData was found (i.e., not an error object indicating mock data isn't loaded)
    // and does not itself contain an error key from a deeper issue (though current getBaseMarketData doesn't produce this)
    if (!marketData.error) {
      console.log(`[MCP Server] Attempting to fetch real data for ${country} from REST Countries API...`);
      try {
        const restCountriesURL = `https://restcountries.com/v3.1/name/${encodeURIComponent(country)}`;
        const realCountryDataResponse = await axios.get(restCountriesURL, { timeout: 7000 }); // 7 second timeout

        if (realCountryDataResponse.status === 200 && realCountryDataResponse.data && realCountryDataResponse.data.length > 0) {
          const countryData = realCountryDataResponse.data[0]; // Take the first result
          marketData.real_population = countryData.population;
          marketData.real_region = countryData.region;
          marketData.real_subregion = countryData.subregion;
          marketData.official_name = countryData.name.official;
          // Add any other fields as needed, e.g.:
          // marketData.capital = countryData.capital ? countryData.capital[0] : 'N/A';
          // marketData.languages = Object.values(countryData.languages || {}).join(', ');
          console.log(`[MCP Server] Successfully fetched and merged real data for ${country}.`);
        } else {
          console.warn(`[MCP Server] REST Countries API did not return expected data for ${country}. Status: ${realCountryDataResponse.status}`);
        }
      } catch (apiError) {
        console.error(`[MCP Server] Failed to fetch real data for ${country} from REST Countries API. Error: ${apiError.message}`);
        if (apiError.response) {
            console.error(`[MCP Server] REST API Error Details: Status ${apiError.response.status}, Data:`, apiError.response.data);
        }
        // Non-critical error, proceed with baseMarketData
      }
    }
      
    // Augment with SerpAPI live web searches
    if (!marketData.error && SERPAPI_API_KEY) { // Only search if no prior error and API key is present
        marketData.live_web_searches = {};
        const query1 = `${country} ${industry} market overview permits regulatory`;
        const query2 = `${country} ${industry} top companies competitors`;
        const query3 = `${country} ${industry} marketing channels social media communities`;

        marketData.live_web_searches.overview_regulatory = await performSerpAPISearch(query1, SERPAPI_API_KEY);
        marketData.live_web_searches.companies_competitors = await performSerpAPISearch(query2, SERPAPI_API_KEY);
        marketData.live_web_searches.marketing_communities = await performSerpAPISearch(query3, SERPAPI_API_KEY);
        console.log(`[MCP Server] Completed SerpAPI searches for ${country} - ${industry}.`);
    } else if (!SERPAPI_API_KEY) {
        console.log("[MCP Server] Skipping SerpAPI searches as API key is not configured.");
        marketData.live_web_searches = {
            overview_regulatory: [],
            companies_competitors: [],
            marketing_communities: [],
            note: "Live web searches skipped due to missing API key."
        };
    }
      
    console.log(`[MCP Server] Returning data for ${country} - ${industry}:`, JSON.stringify(marketData, null, 2)); // Pretty print for easier log reading
    return res.status(200).json(marketData);

  } else {
    console.warn(`[MCP Server] Unknown capability called: ${capability}`);
    return res.status(400).json({ error: `Unknown capability: ${capability}` });
  }
});

app.listen(port, () => {
  console.log(`[MCP Server] MCP Server listening at http://localhost:${port}`);
  if (Object.keys(allData).length === 0) {
    console.warn(`[MCP Server] WARNING: Mock data was not loaded successfully. Check previous logs.`);
  }
  if (!SERPAPI_API_KEY) {
    console.warn("[MCP Server] WARNING: SERPAPI_API_KEY is not set in .env. Live web search functionality will be disabled.");
  }
}); 