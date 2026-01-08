import { GoogleGenAI, Type } from '@google/genai';

export interface Env {
	GEMINI_API_KEY: string;
	APPLE_APP_BUNDLE_ID: string;
}

interface AppleTokenPayload {
	iss: string;
	aud: string;
	exp: number;
	iat: number;
	sub: string;
	email?: string;
}

interface RequestBody {
	image: string;
	mediaType?: string;
}
interface PriceResult {
	price: number | null;
	confidence: 'high' | 'low' | 'none';
}
// Fetch Apple's public keys for token validation
async function getApplePublicKeys(): Promise<any> {
	const response = await fetch('https://appleid.apple.com/auth/keys');
	if (!response.ok) {
		throw new Error('Failed to fetch Apple public keys');
	}
	return response.json();
}

// Decode JWT without verification (to get header)
function decodeJwtHeader(token: string): { kid: string; alg: string } {
	const [headerB64] = token.split('.');
	const header = JSON.parse(atob(headerB64.replace(/-/g, '+').replace(/_/g, '/')));
	return header;
}

// Decode JWT payload
function decodeJwtPayload(token: string): AppleTokenPayload {
	const [, payloadB64] = token.split('.');
	const payload = JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/')));
	return payload;
}

// Convert JWK to CryptoKey
async function jwkToCryptoKey(jwk: JsonWebKey): Promise<CryptoKey> {
	return crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}

// Verify Apple ID token
async function verifyAppleToken(token: string, bundleId: string): Promise<AppleTokenPayload | null> {
	try {
		const header = decodeJwtHeader(token);
		const payload = decodeJwtPayload(token);

		if (payload.exp * 1000 < Date.now()) {
			console.error('Token expired');
			return null;
		}

		if (payload.iss !== 'https://appleid.apple.com') {
			console.error('Invalid issuer');
			return null;
		}

		if (payload.aud !== bundleId) {
			console.error('Invalid audience');
			return null;
		}

		const keysResponse = await getApplePublicKeys();
		const matchingKey = keysResponse.keys.find((key: any) => key.kid === header.kid);

		if (!matchingKey) {
			console.error('No matching key found');
			return null;
		}

		const cryptoKey = await jwkToCryptoKey(matchingKey);
		const [headerB64, payloadB64, signatureB64] = token.split('.');
		const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
		const signature = Uint8Array.from(atob(signatureB64.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

		const isValid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', cryptoKey, signature, data);

		if (!isValid) {
			console.error('Invalid signature');
			return null;
		}

		return payload;
	} catch (error) {
		console.error('Token verification failed:', error);
		return null;
	}
}

// Call Gemini 3 Flash with structured output
async function extractPriceFromImage(apiKey: string, imageBase64: string, mediaType: string): Promise<PriceResult> {
	const ai = new GoogleGenAI({ apiKey });

	const response = await ai.models.generateContent({
		model: 'gemini-3-flash-preview',
		contents: [
			{
				role: 'user',
				parts: [
					{
						inlineData: {
							mimeType: mediaType,
							data: imageBase64,
						},
					},
					{
						text: `Look at this cafe menu image. Find the price for an espresso (not double espresso, not cappuccino, just a regular espresso).

- price: the espresso price as a number (use decimal point, e.g., 2.80). Set to null if not found.
- confidence: "high" if you clearly found it, "low" if you're guessing, "none" if you cannot find it.`,
					},
				],
			},
		],
		config: {
			temperature: 0.1,
			maxOutputTokens: 100,
			responseMimeType: 'application/json',
			responseSchema: {
				type: Type.OBJECT,
				properties: {
					price: {
						type: Type.NUMBER,
						nullable: true,
						description: 'The espresso price as a decimal number, e.g. 2.80',
					},
					confidence: {
						type: Type.STRING,
						enum: ['high', 'low', 'none'],
						description: 'Confidence level of the price detection',
					},
				},
				required: ['price', 'confidence'],
			},
		},
	});

	const text = response.text;
	if (!text) {
		throw new Error('No response from Gemini');
	}

	return JSON.parse(text) as PriceResult;
}

// Main handler
export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const corsHeaders = {
			'Access-Control-Allow-Origin': '*',
			'Access-Control-Allow-Methods': 'POST, OPTIONS',
			'Access-Control-Allow-Headers': 'Content-Type, Authorization',
		};

		if (request.method === 'OPTIONS') {
			return new Response(null, { headers: corsHeaders });
		}

		if (request.method !== 'POST') {
			return new Response(JSON.stringify({ error: 'Method not allowed' }), {
				status: 405,
				headers: { ...corsHeaders, 'Content-Type': 'application/json' },
			});
		}

		try {
			const authHeader = request.headers.get('Authorization');
			if (!authHeader?.startsWith('Bearer ')) {
				return new Response(JSON.stringify({ error: 'Missing authorization token' }), {
					status: 401,
					headers: { ...corsHeaders, 'Content-Type': 'application/json' },
				});
			}

			const token = authHeader.replace('Bearer ', '');
			const appleUser = await verifyAppleToken(token, env.APPLE_APP_BUNDLE_ID);

			if (!appleUser) {
				return new Response(JSON.stringify({ error: 'Invalid or expired token' }), {
					status: 401,
					headers: { ...corsHeaders, 'Content-Type': 'application/json' },
				});
			}

			const body: RequestBody = await request.json();

			if (!body.image) {
				return new Response(JSON.stringify({ error: 'Missing image data' }), {
					status: 400,
					headers: { ...corsHeaders, 'Content-Type': 'application/json' },
				});
			}

			const mediaType = body.mediaType || 'image/jpeg';

			const priceData = await extractPriceFromImage(env.GEMINI_API_KEY, body.image, mediaType);

			return new Response(
				JSON.stringify({
					success: true,
					userId: appleUser.sub,
					email: appleUser.email,
					...priceData,
				}),
				{
					status: 200,
					headers: { ...corsHeaders, 'Content-Type': 'application/json' },
				},
			);
		} catch (error) {
			console.error('Error:', error);
			return new Response(
				JSON.stringify({
					error: 'Internal server error',
					message: error instanceof Error ? error.message : 'Unknown error',
				}),
				{
					status: 500,
					headers: { ...corsHeaders, 'Content-Type': 'application/json' },
				},
			);
		}
	},
};
