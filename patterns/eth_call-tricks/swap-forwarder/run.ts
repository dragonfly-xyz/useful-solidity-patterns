import * as ethers from 'ethers';
import * as crypto from 'crypto';
import * as fs from 'fs';
import { env as ENV } from 'process';

const FORWARDER_ARTIFACT = JSON.parse(fs.readFileSync('../../../out/Contracts.sol/EthSwapForwarder.json', 'utf8'));

// Use a random address to "deploy" our forwarder contract to.
const FORWARDER_ADDRESS = ethers.utils.hexlify(crypto.randomBytes(20));

(async () => {
    // Must have NODE_RPC env var set to a mainnet RPC URL in order to run this example!
    const provider = new ethers.providers.JsonRpcProvider(ENV.NODE_RPC);
    // Point a forwarder contract interface at the address we chose.
    const forwarder = new ethers.Contract(FORWARDER_ADDRESS, FORWARDER_ARTIFACT.abi, provider);
    const rawResult = await provider.send(
        'eth_call',
        [
            {
                ...(await forwarder.populateTransaction.swap()),
                value: ethers.utils.hexValue(ethers.constants.WeiPerEther),
            },
            'pending',
            { [forwarder.address]: { code: FORWARDER_ARTIFACT.deployedBytecode.object } },
        ],
    );
    const daiAmount: ethers.BigNumber = ethers.utils.defaultAbiCoder.decode(['uint256'], rawResult)[0];
    console.log('DAI received from swap:', ethers.utils.formatUnits(daiAmount, 18));
})();
