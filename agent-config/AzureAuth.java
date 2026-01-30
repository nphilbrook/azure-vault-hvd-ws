import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

/**
 * Demonstrates authentication to HashiCorp Vault using the Azure auth method.
 * 
 * This example:
 * 1. Fetches a JWT token from the Azure Instance Metadata Service (IMDS)
 * 2. Retrieves instance metadata (VM name) from IMDS
 * 3. Authenticates to Vault using the Azure auth method
 * 4. Retrieves dynamic database credentials from Vault's database secrets engine
 * 
 * Prerequisites:
 * - Running on an Azure VM with a managed identity attached
 * - Vault configured with the Azure auth method
 * - A role configured in Vault for Azure authentication
 * - Database secrets engine configured at database/creds/my-role
 * 
 * Dependencies:
 * - Gson (com.google.gson:gson:2.10.1 or later)
 * 
 * Environment variables:
 * - VAULT_ADDR: The Vault server address (e.g., https://vault.example.com:8200)
 * - VAULT_ROLE: The Vault role to authenticate as
 * - VAULT_AUTH_PATH: The mount path for Azure auth (default: auth/azure)
 * - AZURE_CLIENT_ID: Optional client ID for user-assigned managed identity
 */
public class AzureAuth {

    // Gson instance for JSON parsing
    private static final Gson gson = new Gson();

    // Azure IMDS endpoint for fetching tokens and metadata
    private static final String IMDS_TOKEN_ENDPOINT = 
        "http://169.254.169.254/metadata/identity/oauth2/token";
    private static final String IMDS_INSTANCE_ENDPOINT = 
        "http://169.254.169.254/metadata/instance";
    
    // Default resource for Azure management API
    private static final String AZURE_RESOURCE = "https://management.azure.com/";
    
    public static void main(String[] args) {
        try {
            String vaultAddr = System.getenv("VAULT_ADDR");
            String vaultRole = System.getenv("VAULT_ROLE");
            String vaultAuthPath = System.getenv("VAULT_AUTH_PATH");
            String azureClientId = System.getenv("AZURE_CLIENT_ID");
            
            if (vaultAddr == null || vaultAddr.isEmpty()) {
                vaultAddr = "http://127.0.0.1:8200";
                System.out.println("VAULT_ADDR not set, using default: " + vaultAddr);
            }
            
            if (vaultRole == null || vaultRole.isEmpty()) {
                vaultRole = "dev-role-azure";
                System.out.println("VAULT_ROLE not set, using default: " + vaultRole);
            }
            
            if (vaultAuthPath == null || vaultAuthPath.isEmpty()) {
                vaultAuthPath = "auth/azure";
                System.out.println("VAULT_AUTH_PATH not set, using default: " + vaultAuthPath);
            }
            
            if (azureClientId != null && !azureClientId.isEmpty()) {
                System.out.println("Using user-assigned managed identity: " + azureClientId);
            }
            
            String secret = getSecretWithAzureAuth(vaultAddr, vaultRole, vaultAuthPath, azureClientId);
            System.out.println("Successfully retrieved secret: " + secret);
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    /**
     * Fetches dynamic database credentials after authenticating to Vault via Azure authentication.
     * This example assumes you have a configured Azure AD Application and database secrets engine.
     * 
     * @param azureClientId Optional client ID for user-assigned managed identity (null for system-assigned)
     */
    public static String getSecretWithAzureAuth(String vaultAddr, String role, String authPath, 
                                                  String azureClientId) throws Exception {
        // Step 1: Get JWT token from Azure IMDS
        System.out.println("Fetching JWT token from Azure IMDS...");
        String jwt = getAzureJwt(AZURE_RESOURCE, azureClientId);
        
        // Step 2: Get instance metadata
        System.out.println("Fetching instance metadata...");
        InstanceMetadata metadata = getInstanceMetadata();
        System.out.println("  Subscription ID: " + metadata.subscriptionId);
        System.out.println("  Resource Group: " + metadata.resourceGroupName);
        System.out.println("  VM Name: " + metadata.vmName);
        
        // Step 3: Login to Vault using Azure auth
        System.out.println("Authenticating to Vault...");
        String vaultToken = loginToVault(vaultAddr, authPath, role, jwt, metadata);
        System.out.println("Successfully authenticated to Vault!");
        
        // Step 4: Fetch database credentials from Vault
        System.out.println("Fetching database credentials from Vault...");
        DatabaseCredentials creds = getDatabaseCredentials(vaultAddr, vaultToken, "database/creds/my-role");
        System.out.println("  Username: " + creds.username);
        System.out.println("  Password: " + creds.password);
        
        return "username=" + creds.username + ", password=" + creds.password;
    }

    /**
     * Fetches a JWT token from the Azure Instance Metadata Service.
     * 
     * @param clientId Optional client ID for user-assigned managed identity (null for system-assigned)
     */
    private static String getAzureJwt(String resource, String clientId) throws Exception {
        String urlStr = IMDS_TOKEN_ENDPOINT + 
            "?api-version=2018-02-01" +
            "&resource=" + java.net.URLEncoder.encode(resource, "UTF-8");
        
        // Add client_id for user-assigned managed identity
        if (clientId != null && !clientId.isEmpty()) {
            urlStr += "&client_id=" + java.net.URLEncoder.encode(clientId, "UTF-8");
        }
        
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Metadata", "true");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        
        int responseCode = conn.getResponseCode();
        if (responseCode != 200) {
            throw new RuntimeException("Failed to get Azure token. HTTP " + responseCode + 
                ". Are you running on an Azure VM with managed identity?");
        }
        
        String response = readResponse(conn);
        
        // Parse the access_token from JSON response
        JsonObject json = gson.fromJson(response, JsonObject.class);
        if (!json.has("access_token")) {
            throw new RuntimeException("No access_token in IMDS response");
        }
        
        return json.get("access_token").getAsString();
    }

    /**
     * Fetches instance metadata from the Azure IMDS.
     */
    private static InstanceMetadata getInstanceMetadata() throws Exception {
        String urlStr = IMDS_INSTANCE_ENDPOINT + "?api-version=2021-02-01";
        
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Metadata", "true");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        
        int responseCode = conn.getResponseCode();
        if (responseCode != 200) {
            throw new RuntimeException("Failed to get instance metadata. HTTP " + responseCode);
        }
        
        String response = readResponse(conn);
        
        // Parse the compute section from the JSON response
        JsonObject json = gson.fromJson(response, JsonObject.class);
        JsonObject compute = json.getAsJsonObject("compute");
        
        InstanceMetadata metadata = new InstanceMetadata();
        metadata.subscriptionId = compute.get("subscriptionId").getAsString();
        metadata.resourceGroupName = compute.get("resourceGroupName").getAsString();
        metadata.vmName = compute.get("name").getAsString();
        
        return metadata;
    }

    /**
     * Logs in to Vault using the Azure auth method.
     */
    private static String loginToVault(String vaultAddr, String authPath, String role, String jwt, 
                                         InstanceMetadata metadata) throws Exception {
        // Remove trailing slash from vaultAddr if present
        if (vaultAddr.endsWith("/")) {
            vaultAddr = vaultAddr.substring(0, vaultAddr.length() - 1);
        }
        
        String urlStr = vaultAddr + "/v1/" + authPath + "/login";
        System.out.println("Login URL: " + urlStr);
        
        // Build JSON payload (omitting subscription_id and resource_group_name)
        JsonObject payloadObj = new JsonObject();
        payloadObj.addProperty("role", role);
        payloadObj.addProperty("jwt", jwt);
        payloadObj.addProperty("vm_name", metadata.vmName);
        String payload = gson.toJson(payloadObj);
        
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setDoOutput(true);
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(10000);
        
        try (OutputStream os = conn.getOutputStream()) {
            os.write(payload.getBytes(StandardCharsets.UTF_8));
        }
        
        int responseCode = conn.getResponseCode();
        if (responseCode != 200) {
            String errorBody = readErrorResponse(conn);
            throw new RuntimeException("Vault login failed. HTTP " + responseCode + ": " + errorBody);
        }
        
        String response = readResponse(conn);
        
        // Parse the client_token from the auth section
        JsonObject json = gson.fromJson(response, JsonObject.class);
        JsonObject auth = json.getAsJsonObject("auth");
        if (auth == null || !auth.has("client_token")) {
            throw new RuntimeException("No client_token in Vault login response");
        }
        
        return auth.get("client_token").getAsString();
    }

    /**
     * Retrieves dynamic database credentials from Vault's database secrets engine.
     */
    private static DatabaseCredentials getDatabaseCredentials(String vaultAddr, String token, 
                                                                String path) throws Exception {
        // Remove trailing slash from vaultAddr if present
        if (vaultAddr.endsWith("/")) {
            vaultAddr = vaultAddr.substring(0, vaultAddr.length() - 1);
        }
        
        String urlStr = vaultAddr + "/v1/" + path;
        System.out.println("Database credentials URL: " + urlStr);
        
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("X-Vault-Token", token);
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(10000);
        
        int responseCode = conn.getResponseCode();
        if (responseCode != 200) {
            String errorBody = readErrorResponse(conn);
            throw new RuntimeException("Failed to read database credentials. HTTP " + responseCode + ": " + errorBody);
        }
        
        String response = readResponse(conn);
        
        // Parse the credentials from the data section
        // Database secrets engine format: {"data": {"username": "...", "password": "..."}, ...}
        JsonObject json = gson.fromJson(response, JsonObject.class);
        JsonObject data = json.getAsJsonObject("data");
        
        if (data == null || !data.has("username") || !data.has("password")) {
            throw new RuntimeException("Missing username or password in database credentials response");
        }
        
        DatabaseCredentials creds = new DatabaseCredentials();
        creds.username = data.get("username").getAsString();
        creds.password = data.get("password").getAsString();
        
        return creds;
    }
    
    /**
     * Container for database credentials.
     */
    private static class DatabaseCredentials {
        String username;
        String password;
    }

    // Helper methods for HTTP and JSON parsing

    private static String readResponse(HttpURLConnection conn) throws Exception {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
            return reader.lines().collect(Collectors.joining("\n"));
        }
    }

    private static String readErrorResponse(HttpURLConnection conn) {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(conn.getErrorStream(), StandardCharsets.UTF_8))) {
            return reader.lines().collect(Collectors.joining("\n"));
        } catch (Exception e) {
            return "(unable to read error response)";
        }
    }

    /**
     * Simple container for instance metadata.
     */
    private static class InstanceMetadata {
        String subscriptionId;
        String resourceGroupName;
        String vmName;
    }
}
