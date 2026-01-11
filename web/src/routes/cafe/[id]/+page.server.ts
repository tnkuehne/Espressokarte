import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, platform }) => {
	// Get tokens from environment variables
	const mapkitToken = platform?.env?.MAPKIT_JWT_TOKEN || '';
	const cloudkitToken = platform?.env?.CLOUDKIT_API_TOKEN || '';

	return {
		cafeId: params.id,
		mapkitToken,
		cloudkitToken
	};
};
