import React from 'react';
import { Leaf, Sparkles, Zap, Copy } from 'lucide-react';

export function Hero() {
  const [copiedEth, setCopiedEth] = React.useState(false);
  const [copiedSol, setCopiedSol] = React.useState(false);
  const contractAddresses = {
    eth: '0x39A0ec7F51f4BA8CbCb3D149FC4583da6805D58C',
    sol: 'AaTRjrsnXXFza4SHvejKm1HHqHWmjU8dgPNCt2r2pump'
  };

  const copyToClipboard = async (chain: 'eth' | 'sol') => {
    try {
      await navigator.clipboard.writeText(contractAddresses[chain]);
      if (chain === 'eth') {
        setCopiedEth(true);
        setTimeout(() => setCopiedEth(false), 2000);
      } else {
        setCopiedSol(true);
        setTimeout(() => setCopiedSol(false), 2000);
      }
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  return (
    <section id="home" className="min-h-screen pt-20 relative overflow-hidden">
      <div className="container mx-auto px-6 relative">
        <div className="flex flex-col items-center text-center pt-20">
          <div className="mb-8 floating">
            <video 
              autoPlay 
              loop 
              muted 
              playsInline
              className="w-32 h-32 rounded-full border-4 border-emerald-400 shadow-lg object-cover"
            >
              <source src="https://media.giphy.com/media/EatwJZRUIv41G/giphy.mp4" type="video/mp4" />
              Your browser does not support the video tag.
            </video>
          </div>
          
          <div className="backdrop-blur-sm bg-white/10 rounded-2xl p-8 mb-8">
            <h1 className="text-5xl md:text-7xl font-bold text-white mb-6">
              Welcome to Mei Mei's World
            </h1>
            
            <p className="text-2xl md:text-3xl text-emerald-700 max-w-2xl mx-auto">
              Where Nature Meets the Digital Frontier
            </p>
          </div>
          
          <div className="flex flex-col sm:flex-row gap-4 mb-16">
            <a
              href="https://kids.guinnessworldrecords.com/news/2019/7/twin-pandas-born-in-china-make-history-in-conservation-first-582453"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-gradient-to-r from-emerald-500 to-cyan-500 text-white rounded-full hover:from-emerald-400 hover:to-cyan-400 transition-all transform hover:scale-105 neon-border"
            >
              Our Story
            </a>
            <a
              href="https://app.uniswap.org/swap?chain=mainnet&inputCurrency=NATIVE&outputCurrency=0x39A0ec7F51f4BA8CbCb3D149FC4583da6805D58C"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-gradient-to-r from-pink-500 to-purple-500 text-white rounded-full hover:from-pink-400 hover:to-purple-400 transition-all transform hover:scale-105 neon-border"
            >
              Buy Token
            </a>
            <a
              href="https://dexscreener.com/ethereum/0x39A0ec7F51f4BA8CbCb3D149FC4583da6805D58C"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-gradient-to-r from-blue-500 to-indigo-500 text-white rounded-full hover:from-blue-400 hover:to-indigo-400 transition-all transform hover:scale-105 neon-border"
            >
              Chart
            </a>
            <a
              href="https://pump.fun/AaTRjrsnXXFza4SHvejKm1HHqHWmjU8dgPNCt2r2pump"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-4 bg-gradient-to-r from-yellow-500 to-orange-500 text-white rounded-full hover:from-yellow-400 hover:to-orange-400 transition-all transform hover:scale-105 neon-border"
            >
              pump.fun
            </a>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-4xl mb-16">
            {[
              { icon: Leaf, title: 'Eco-Friendly', value: '100%' },
              { icon: Zap, title: 'Energy Efficient', value: '99.9%' },
              { icon: Sparkles, title: 'Digital Forest', value: '10,000+' }
            ].map((stat) => (
              <div key={stat.title} className="bg-white rounded-2xl p-6 shadow-lg floating text-center" style={{ animationDelay: Math.random() + 's' }}>
                <stat.icon className="w-8 h-8 text-emerald-600 mb-2 mx-auto" />
                <div className="text-3xl font-bold text-emerald-600">{stat.value}</div>
                <div className="text-xl text-emerald-700">{stat.title}</div>
              </div>
            ))}
          </div>

          {/* Contract Addresses */}
          <div className="max-w-2xl w-full space-y-4">
            <h3 className="text-2xl font-bold text-white mb-3">
              Contract Addresses
            </h3>
            
            {/* ETH Address */}
            <div className="bg-white rounded-2xl p-4 shadow-lg">
              <div className="text-lg font-semibold text-emerald-700 mb-2">ETH</div>
              <div className="flex items-center justify-between p-2 bg-emerald-50 rounded-lg border-2 border-emerald-200">
                <code className="text-lg text-emerald-600 font-mono truncate max-w-[calc(100%-100px)] px-2">
                  {contractAddresses.eth}
                </code>
                <button 
                  onClick={() => copyToClipboard('eth')}
                  className="px-3 py-1.5 bg-emerald-600 text-white rounded-lg hover:bg-emerald-500 transition-colors flex items-center gap-1.5 flex-shrink-0"
                >
                  <span>{copiedEth ? 'Copied!' : 'Copy'}</span>
                  <Copy className="w-4 h-4" />
                </button>
              </div>
            </div>

            {/* SOL Address */}
            <div className="bg-white rounded-2xl p-4 shadow-lg">
              <div className="text-lg font-semibold text-emerald-700 mb-2">SOL</div>
              <div className="flex items-center justify-between p-2 bg-emerald-50 rounded-lg border-2 border-emerald-200">
                <code className="text-lg text-emerald-600 font-mono truncate max-w-[calc(100%-100px)] px-2">
                  {contractAddresses.sol}
                </code>
                <button 
                  onClick={() => copyToClipboard('sol')}
                  className="px-3 py-1.5 bg-emerald-600 text-white rounded-lg hover:bg-emerald-500 transition-colors flex items-center gap-1.5 flex-shrink-0"
                >
                  <span>{copiedSol ? 'Copied!' : 'Copy'}</span>
                  <Copy className="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}