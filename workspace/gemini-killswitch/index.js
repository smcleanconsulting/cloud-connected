// index.js
const express = require('express');
const { CloudBillingClient } = require('@google-cloud/billing');
// Removed @google-cloud/compute as it wasn't used in the billing logic

const app = express();
app.use(express.json()); // Middleware to parse JSON request bodies

const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT;
const PROJECT_NAME = `projects/${PROJECT_ID}`;
const billing = new CloudBillingClient();

// This is the endpoint that Eventarc (triggered by Pub/Sub) will send the message to
app.post('/', async (req, res) => {
  console.log('Received request from Eventarc/PubSub.');

  try {
    // Eventarc sends the Pub/Sub message data inside the 'message.data' field
    // of the HTTP request body, base64 encoded.
    if (!req.body || !req.body.message || !req.body.message.data) {
      console.error('Invalid request body format. Expected Pub/Sub message data.');
      return res.status(400).send('Bad Request: Missing Pub/Sub message data.');
    }

    const pubsubData = JSON.parse(
      Buffer.from(req.body.message.data, 'base64').toString()
    );

    console.log('Parsed Pub/Sub data:', pubsubData);

    // --- Original Budget Check Logic ---
    if (pubsubData.costAmount <= pubsubData.budgetAmount) {
      const message = `No action necessary. (Current cost: ${pubsubData.costAmount}, Budget: ${pubsubData.budgetAmount})`;
      console.log(message);
      return res.status(200).send(message); // Respond 200 for no action
    }

    console.log(`Budget exceeded! Current cost: ${pubsubData.costAmount}, Budget: ${pubsubData.budgetAmount}. Proceeding to check and disable billing.`);

    // --- Original Billing Logic ---
    if (!PROJECT_ID) {
      const message = 'Error: No project specified via GOOGLE_CLOUD_PROJECT environment variable.';
      console.error(message);
      return res.status(500).send(message); // Indicate server error
    }

    const billingEnabled = await _isBillingEnabled(PROJECT_NAME);

    if (billingEnabled) {
      console.log('Billing is enabled. Attempting to disable...');
      // _disableBillingForProject handles the API call and returns a result string
      const result = await _disableBillingForProject(PROJECT_NAME);
      console.log('Billing disable attempt result:', result);
      return res.status(200).send(result); // Respond 200 on successful API call (check result content)
    } else {
      const message = 'Billing already disabled. No action taken.';
      console.log(message);
      return res.status(200).send(message); // Respond 200 if already disabled
    }

  } catch (error) {
    console.error('Error processing request:', error);
    // Return 500 on unhandled errors to indicate failure
    res.status(500).send('Internal Server Error: ' + error.message);
  }
});

/**
 * Determine whether billing is enabled for a project
 * @param {string} projectName Name of project to check if billing is enabled
 * @return {bool} Whether project has billing enabled or not
 */
const _isBillingEnabled = async projectName => {
  try {
    const [res] = await billing.getProjectBillingInfo({name: projectName});
    console.log(`Billing info for ${projectName}: enabled=${res.billingEnabled}, account=${res.billingAccountName}`);
    return res.billingEnabled;
  } catch (e) {
    console.error(
      `Error determining if billing is enabled on ${projectName}:`, e
    );
     // IMPORTANT: If we can't check billing status, should we proceed assuming enabled or bail?
     // Assuming true might lead to unnecessary disable attempts, but bailing might miss disabling.
     // Current logic assumes true on error. Review this behavior for production.
    return true; // Assume billing is enabled on error for safety
  }
};

/**
 * Disable billing for a project by removing its billing account
 * @param {string} projectName Name of project disable billing on
 * @return {string} Text containing response from disabling billing
 */
const _disableBillingForProject = async projectName => {
  try {
    console.log(`Calling billing API to updateProjectBillingInfo for ${projectName} with billingAccountName: ''`);
    const [res] = await billing.updateProjectBillingInfo({
      name: projectName,
      projectBillingInfo: {billingAccountName: ''}, // Disable billing
    });
    console.log(`API response for disabling billing on ${projectName}:`, res);
    // Check if the billingAccountName is actually detached in the response
     if (res && res.billingAccountName === '') {
         return `SUCCESS: Billing disabled for ${projectName}.`;
     } else {
         console.warn(`API call succeeded but billing account is still attached or unexpected response for ${projectName}.`);
         return `WARNING: API call successful, but verification failed for ${projectName}. Response: ${JSON.stringify(res)}`;
     }
  } catch (e) {
    console.error(`FATAL ERROR: Failed to disable billing for ${projectName}:`, e);
    throw e; // Re-throw to be caught by the main error handler
  }
};


// --- Start the HTTP server ---
// Cloud Run and Cloud Functions 2nd Gen provide the port via the PORT environment variable
const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Billing killswitch server listening on port ${port}`);
});