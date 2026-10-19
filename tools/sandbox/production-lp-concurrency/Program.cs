using System.Net.Http.Headers;
using System.Text;
using Microsoft.Dynamics.Nav.Deployment;
using Microsoft.Dynamics.Nav.Deployment.Authentication;

static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("usage: bcapi-helper METHOD URL [BODY_FILE]");
            return 2;
        }

        var target = new Uri(args[1]);
        if (target.Scheme != "https" || target.Host != "api.businesscentral.dynamics.com" ||
            !target.AbsolutePath.StartsWith("/v2.0/3bbd610b-95e4-47b3-8b48-4f7caf717bc3/sand0309/", StringComparison.OrdinalIgnoreCase))
            throw new Exception("Only sand0309 sandbox URLs are allowed.");

        Console.Error.WriteLine("Authenticating for sand0309...");
        var result = await EntraIdAuthService.LoginAsync(new QuietLogger(), new EntraIdLoginParameters
        {
            Environment = PublishEnvironment.Production,
            EnvironmentType = EnvironmentType.Sandbox,
            EnvironmentName = "sand0309",
            Tenant = "3bbd610b-95e4-47b3-8b48-4f7caf717bc3",
            ApplicationFamily = "BusinessCentral",
            UseInteractiveLogin = false,
            AllowDeviceCodeFallback = false,
        });

        if (!result.Success || string.IsNullOrWhiteSpace(result.AccessToken))
        {
            Console.Error.WriteLine($"Authentication failed: {result.Error}");
            return 3;
        }

        Console.Error.WriteLine("Authenticated; sending sandbox request.");
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        client.DefaultRequestHeaders.TryAddWithoutValidation("If-Match", "*");

        if (args[0] == "CONCURRENT")
        {
            var body = await File.ReadAllTextAsync(args[2]);
            var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            async Task<object> Send(int index)
            {
                using var concurrentClient = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
                concurrentClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                concurrentClient.DefaultRequestHeaders.TryAddWithoutValidation("If-Match", "*");
                await gate.Task;
                var started = DateTimeOffset.UtcNow;
                using var req = new HttpRequestMessage(HttpMethod.Post, args[1]);
                req.Content = new StringContent(index == 2 && args.Length > 3 ? await File.ReadAllTextAsync(args[3]) : body, Encoding.UTF8, "application/json");
                using var res = await concurrentClient.SendAsync(req);
                return new { index, started, ended = DateTimeOffset.UtcNow, status = (int)res.StatusCode, body = await res.Content.ReadAsStringAsync() };
            }
            var requests = new[] { Send(1), Send(2) };
            gate.SetResult();
            Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(await Task.WhenAll(requests)));
            return 0;
        }

        using var request = new HttpRequestMessage(new HttpMethod(args[0]), args[1]);
        if (args.Length > 2)
            request.Content = new StringContent(await File.ReadAllTextAsync(args[2]), Encoding.UTF8, "application/json");

        using var response = await client.SendAsync(request);
        Console.WriteLine($"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
        Console.WriteLine(await response.Content.ReadAsStringAsync());
        return response.IsSuccessStatusCode ? 0 : 4;
    }
}

sealed class QuietLogger : IEmitLogger
{
    public void Info(string message, params object[] args) { }
    public void Error(string message, params object[] args) => Console.Error.WriteLine(message, args);
    public void Error(string message) => Console.Error.WriteLine(message);
    public void Exception(Exception ex) => Console.Error.WriteLine(ex.Message);
    public void ShowDeviceLoginDialog(string message, string uri, string token) =>
        Console.Error.WriteLine($"Interactive login required: {uri}");
    public void OpenUri(string uri) => Console.Error.WriteLine("Interactive login required.");
    public void NetworkException(Exception ex) => Console.Error.WriteLine(ex.Message);
}
