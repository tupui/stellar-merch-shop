import React from "react";
import { Layout, Text } from "@stellar/design-system";
import { NFCMintProduct } from "../components/NFCMintProduct";

const Home: React.FC = () => (
  <Layout.Content>
    <Layout.Inset>
      <Text as="h1" size="xl">
        Welcome to the Stellar Merch Shop app!
      </Text>
      <Text as="p" size="md">
        This app integrates with Infineon NFC chips to mint NFTs linked to physical products.
        Place your chip on the uTrust 4701F reader and click mint to get started.
      </Text>
      <Text as="h2" size="lg">
        Mint NFT from NFC Chip
      </Text>
      <NFCMintProduct />
    </Layout.Inset>
  </Layout.Content>
);

export default Home;

