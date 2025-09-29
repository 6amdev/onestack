// Cloud Code functions

Parse.Cloud.define('hello', async (request) => {
  return 'Hello from OneStack!';
});

// Before save hook example
Parse.Cloud.beforeSave('User', async (request) => {
  const user = request.object;
  
  // Add validation or modification here
  if (!user.get('email')) {
    throw new Parse.Error(400, 'Email is required');
  }
});

// After save hook example
Parse.Cloud.afterSave('User', async (request) => {
  const user = request.object;
  console.log('New user created:', user.id);
  
  // Send welcome email, etc.
});

// Scheduled job example (requires parse-server 5.0+)
if (Parse.Cloud.job) {
  Parse.Cloud.job('dailyCleanup', async (request) => {
    // Daily cleanup tasks
    console.log('Running daily cleanup...');
    return { success: true };
  });
}