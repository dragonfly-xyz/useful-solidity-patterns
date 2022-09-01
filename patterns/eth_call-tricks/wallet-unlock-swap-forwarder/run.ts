import * as ethers from 'ethers';
import * as crypto from 'crypto';
import * as fs from 'fs';
import { env as ENV } from 'process';

const FORWARDER_ARTIFACT = JSON.parse(fs.readFileSync('../../../out/Contracts.sol/DaiSwapForwarder.json', 'utf8'));
const WALLET_ARTIFACT = JSON.parse(fs.readFileSync('../../../out/Contracts.sol/UnlockedWallet.json', 'utf8'));

// Use a random address to "deploy" our forwarder contract to.
const FORWARDER_ADDRESS = ethers.utils.hexlify(crypto.randomBytes(20));
// A known wallet holding lots of DAI.
const DAI_WALLET = '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643';

(async () => {
    // Must have NODE_RPC env var set to a mainnet RPC URL in order to run this example!
    const provider = new ethers.providers.JsonRpcProvider(ENV.NODE_RPC);
    // Point a forwarder contract interface at the address we chose.
    const forwarder = new ethers.Contract(FORWARDER_ADDRESS, FORWARDER_ARTIFACT.abi, provider);
    const rawResult = await provider.send(
        'eth_call',
        [
            await forwarder.populateTransaction.swap(DAI_WALLET, ethers.constants.WeiPerEther.mul(100)),
            'pending',
            {
                [forwarder.address]: { code: FORWARDER_ARTIFACT.deployedBytecode.object },
                [DAI_WALLET]: { code: WALLET_ARTIFACT.deployedBytecode.object }
            },
        ],
    );
    const ethAmount: ethers.BigNumber = ethers.utils.defaultAbiCoder.decode(['uint256'], rawResult)[0];
    console.log('ETH received from swap:', ethers.utils.formatUnits(ethAmount, 18));
})();
