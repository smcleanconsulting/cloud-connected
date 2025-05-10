// index.js
const functions = require('@google-cloud/functions-framework');
const { CloudBillingClient } = require('@google-cloud/billing');
// Removed express, @google-cloud/compute, etc.

const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT;
const PROJECT_NAME = `projects/${PROJECT_ID}`;
const billing = new CloudBillingClient();

// Register a CloudEvent handler with the functions-framework
// This handler will be invoked by the Pub/Sub trigger via Eventarc
functions.cloudEvent('stopBillingHandler', async cloudEvent => {
  console.log('Received CloudEvent from Pub/Sub trigger.');

  try {
    // The Pub/Sub message data is within the cloudEvent object
    // The exact path might vary slightly depending on the event structure,
    // but for Pub/Sub it's typically in cloudEvent.data.message.data
    if (!cloudEvent.data || !cloudEvent.data.message || !cloudEvent.data.message.data) {
      console.error('Invalid CloudEvent data format. Expected Pub/Sub message data.');
      // For background triggers, throwing an error indicates failure and might trigger retries
      throw new Error('Missing Pub/Sub message data in CloudEvent.');
    }

    const pubsubData = JSON.parse(
      Buffer.from(cloudEvent.data.message.data, 'base64').toString()
    );

    console.log('Parsed Pub/Sub data:', pubsubData);

    // --- Original Budget Check Logic ---
    if (pubsubData.costAmount <= pubsubData.budgetAmount) {
      console.log(`No action necessary. (Current cost: ${pubsubData.costAmount}, Budget: ${pubsubData.budgetAmount})`);
      return; // Exit the function if no action needed
    }

    console.log(`Budget exceeded! Current cost: ${pubsubData.costAmount}, Budget: ${pubsubData.budgetAmount}. Proceeding to check and disable billing.`);

    // --- Original Billing Logic ---
    if (!PROJECT_ID) {
      console.error('Error: No project specified via GOOGLE_CLOUD_PROJECT environment variable.');
      throw new Error('Project ID not available.'); // Indicate fatal error
    }

    const billingEnabled = await _isBillingEnabled(PROJECT_NAME);

    if (billingEnabled) {
      console.log('Billing is enabled. Attempting to disable...');
      // _disableBillingForProject handles the API call
      await _disableBillingForProject(PROJECT_NAME); // Throw error if disable fails
      console.log('Billing disable process completed.');
    } else {
      console.log('Billing already disabled. No action taken.');
    }

  } catch (error) {
    console.error('Error processing CloudEvent:', error);
    throw error; // Re-throw to indicate failure to the platform
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
         console.log(`SUCCESS: Billing disabled for ${projectName}.`);
     } else {
         console.warn(`API call succeeded but billing account is still attached or unexpected response for ${projectName}.`);
         // Throw an error here if detachment MUST be verified
         throw new Error(`Billing detachment verification failed for ${projectName}.`);
     }
  } catch (e) {
    console.error(`FATAL ERROR: Failed to disable billing for ${projectName}:`, e);
    throw e; // Re-throw to be caught by the main error handler
  }
};

// Note: No app.listen() or HTTP server code is needed here.
// The functions-framework handles receiving the CloudEvent via HTTP internally.